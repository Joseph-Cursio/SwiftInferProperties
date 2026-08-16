import Foundation
import Testing

/// The cross-repo half of the SEI pin invariant: **this package and
/// SwiftProjectLint must pin the same `SwiftEffectInference` revision.**
///
/// The claim the shared leaf exists to support is that *the linter and the
/// inference engine can never disagree about what is pure*. That is a statement
/// about the **oracle they compile against**, not about the repository — so it
/// holds only while the pins are equal, and nothing checked that until now.
///
/// SwiftProjectLint's own `SEIPinAgreementTests` guards its three manifests
/// against each other, and says plainly what it cannot reach: *"This test cannot
/// see that cross-repo gap; nothing in a single repository can."* That is true of
/// a test compiled from one package's sources. It is not true of a test willing
/// to look on disk, which is what this one does.
///
/// ## Why it was written on a day when it passes
///
/// 2026-08-16. The pins had just been brought back into agreement, so this guard
/// catches nothing at the moment it is added — the weakest possible motivation,
/// and the reason it kept not being written.
///
/// What changed is the failure it would have caught. Every earlier divergence in
/// this project's record was **docs-only and inert**: a README repair, a PRD
/// citation. That day's was the first across real source — SEI grew
/// `NondeterminismSources` and `ClockDeterminismRefuter`, SwiftProjectLint
/// bumped to consume them, and for several hours the two consumers compiled
/// against different oracles. It opened and closed inside one day and **nothing
/// reported it**. A guard written only when it fails is a guard written after
/// the damage; the divergences here have always been noticed by someone
/// re-reading a manifest, which is not a mechanism.
///
/// ## What this can and cannot see
///
/// It needs SwiftProjectLint **checked out on the same machine**. It looks in
/// `SWIFTPROJECTLINT_ROOT` first, then at the sibling directory beside this
/// package — the layout this project is developed in. When it finds nothing it
/// **skips**, and the skip is deliberately loud rather than a silent pass: a
/// green test that verified nothing is the exact failure mode this repository
/// keeps writing documents about.
///
/// So it is a **developer-machine guard, not a CI gate**, and the honest
/// statement of its power is: it catches the pin drifting on the machine where
/// somebody is bumping pins, which is where the drift is created. Closing the
/// remaining hole needs a release-time check with both repositories in hand —
/// out of scope for a unit test, and worth building only if this one is seen to
/// skip in practice.
@Suite("Packaging — the SEI pin matches SwiftProjectLint's")
struct SEICrossRepoPinTests {

    // MARK: - Locating the sibling consumer

    /// Environment override, for a checkout that is not beside this one.
    private static let rootEnvironmentKey = "SWIFTPROJECTLINT_ROOT"

    /// This package's root, resolved from this file rather than the process
    /// working directory, which `swift test` does not guarantee.
    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftInferCLITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // <package root>
    }

    /// Every place this guard is willing to look, in order. Exposed so the
    /// skip message can name them — a skip whose reason is "not found" is only
    /// actionable if it says where it searched.
    static var candidateRoots: [URL] {
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment[rootEnvironmentKey],
           !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }
        candidates.append(
            packageRoot.deletingLastPathComponent().appendingPathComponent("SwiftProjectLint")
        )
        return candidates
    }

    /// The first candidate that looks like SwiftProjectLint — meaning its root
    /// manifest exists **and** declares SEI. Checking for the dependency rather
    /// than merely for a directory is what stops an unrelated folder of the
    /// right name from satisfying the guard.
    static var swiftProjectLintRoot: URL? {
        candidateRoots.first { root in
            let manifest = root.appendingPathComponent("Package.swift")
            guard let text = try? String(contentsOf: manifest, encoding: .utf8) else { return false }
            return text.contains("SwiftEffectInference.git")
        }
    }

    // MARK: - Reading a pin

    /// The manifests that must agree. This package has one; SwiftProjectLint
    /// declares SEI in three, and all four are the invariant — comparing only
    /// the roots would pass while the linter's nested packages sat behind.
    private static let swiftProjectLintManifests = [
        "Package.swift",
        "Packages/SwiftProjectLintVisitors/Package.swift",
        "Packages/SwiftProjectLintIdempotencyRules/Package.swift"
    ]

    /// The revision a manifest pins SEI to.
    ///
    /// Parsed from the manifest **text**, deliberately, and for the same reason
    /// SwiftProjectLint's own guard gives: `Package.resolved` is a build
    /// artefact a stale checkout can carry, while the manifest is the
    /// declaration under test. A guard reading resolved state would agree with
    /// itself while the sources disagreed.
    static func pinnedRevision(inManifestAt url: URL) throws -> String {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let index = lines.firstIndex(where: { $0.contains("SwiftEffectInference.git") }) else {
            throw PinError.noDependency(url.path)
        }
        for line in lines[index ..< min(index + 5, lines.count)] {
            guard let range = line.range(of: "revision:") else { continue }
            let revision = line[range.upperBound...].filter(\.isHexDigit)
            guard revision.count == 40 else { continue }
            return String(revision)
        }
        throw PinError.noRevision(url.path)
    }

    enum PinError: Error, CustomStringConvertible {
        case noDependency(String)
        case noRevision(String)

        var description: String {
            switch self {
            case let .noDependency(path):
                return "\(path) declares no SwiftEffectInference dependency"

            case let .noRevision(path):
                return "\(path) pins SwiftEffectInference without a 40-char revision"
            }
        }
    }

    // MARK: - The guard

    @Test(
        "This package and SwiftProjectLint pin the same SEI revision",
        .enabled(if: swiftProjectLintRoot != nil)
    )
    func pinMatchesSwiftProjectLint() throws {
        let linterRoot = try #require(
            Self.swiftProjectLintRoot,
            "guarded by .enabled(if:) — unreachable"
        )

        var pins = [(manifest: String, revision: String)]()
        pins.append((
            "SwiftInferProperties/Package.swift",
            try Self.pinnedRevision(inManifestAt: Self.packageRoot.appendingPathComponent("Package.swift"))
        ))
        for manifest in Self.swiftProjectLintManifests {
            pins.append((
                "SwiftProjectLint/\(manifest)",
                try Self.pinnedRevision(inManifestAt: linterRoot.appendingPathComponent(manifest))
            ))
        }

        let distinct = Set(pins.map(\.revision))
        #expect(
            distinct.count == 1,
            """
            The two consumers of SwiftEffectInference pin different revisions, so the linter and \
            the inference engine are not consulting one purity oracle. Bump them together:
            \(pins.map { "  \($0.manifest): \($0.revision)" }.joined(separator: "\n"))
            """
        )
    }

    /// The non-vacuity guard, and the reason this suite is two tests rather
    /// than one.
    ///
    /// The test above is skipped when SwiftProjectLint is not found. A bug in
    /// the locator — a wrong path component, a renamed directory, an
    /// environment variable read from the wrong key — would therefore disable
    /// the guard **permanently and invisibly**, and the suite would stay green
    /// while checking nothing. That is the precise failure this whole invariant
    /// exists to prevent, so it must not be the way the invariant is enforced.
    ///
    /// This test always runs. It cannot assert that the sibling is present —
    /// that legitimately depends on the machine — but it can assert the guard
    /// is *capable* of finding it: that the search list is well-formed and
    /// absolute, that this package's own pin parses, and, when a root was
    /// found, that all of the linter's manifests parse too. A skip then means
    /// "not checked out here", never "the locator is broken".
    @Test("The guard can locate and parse pins, whether or not the sibling is present")
    func guardIsCapableOfChecking() throws {
        let candidates = Self.candidateRoots
        #expect(!candidates.isEmpty, "the guard would never find anything")
        for candidate in candidates {
            #expect(candidate.path.hasPrefix("/"), "candidate is not absolute: \(candidate.path)")
        }

        // This package's own pin must always parse — it is in this repository,
        // so failing here is a broken parser rather than a missing checkout.
        let ownPin = try Self.pinnedRevision(
            inManifestAt: Self.packageRoot.appendingPathComponent("Package.swift")
        )
        // Bound before asserting: `#expect` decomposes a function call and
        // treats the key-path argument as throwing, so the inline form does not
        // compile. SwiftProjectLint's guard has the same shape for the same reason.
        let ownPinIsHex = ownPin.allSatisfy(\.isHexDigit)
        #expect(ownPin.count == 40)
        #expect(ownPinIsHex)

        guard let linterRoot = Self.swiftProjectLintRoot else {
            // Printed, not recorded as an issue. A machine legitimately holding
            // only this repository must not go red — `Issue.record` fails the
            // test, which would make the guard hostile to a fresh clone and
            // invite someone to delete it.
            //
            // The visibility the skip needs comes from `.enabled(if:)` on the
            // comparison above, which the runner reports as an explicit
            // `skipped` line. This print says *why* and where it looked, so the
            // skip is diagnosable rather than merely announced.
            print(
                """
                NOTE — cross-repo pin comparison SKIPPED: SwiftProjectLint not found. \
                Set \(Self.rootEnvironmentKey) or check it out beside this package. Searched:
                \(candidates.map { "  \($0.path)" }.joined(separator: "\n"))
                """
            )
            return
        }

        for manifest in Self.swiftProjectLintManifests {
            let pin = try Self.pinnedRevision(inManifestAt: linterRoot.appendingPathComponent(manifest))
            let pinIsHex = pin.allSatisfy(\.isHexDigit)
            #expect(pin.count == 40, "SwiftProjectLint/\(manifest) → \(pin)")
            #expect(pinIsHex, "SwiftProjectLint/\(manifest) → \(pin)")
        }
    }
}
