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
/// **An equal pin is NECESSARY, and since 2026-10-06 it is not SUFFICIENT.** Both
/// consumers now configure the oracle with SEI's `ConstructionFacts`, a table built
/// from a *file universe* — and the same pin over two universes is the same oracle
/// configured two ways, answering differently about the same function. So one
/// oracle needs an equal pin **and** an equal universe. The universe rule is written
/// twice (here `ConstructionUniverse`, there its SwiftProjectLint twin), and what keeps
/// the two from drifting is a byte-identical answer key both repos assert their
/// predicate over: `universeTableMatchesSwiftProjectLint` below is the cross-repo half
/// of that, and skips as loudly as the pin check when the sibling's copy is absent.
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

    // MARK: - The shared universe table

    /// Where SwiftProjectLint keeps its copy of the shared construction-universe table.
    static let linterUniverseTablePath = "Docs/construction-universe.tsv"

    /// This package's copy.
    static var ownUniverseTable: URL {
        packageRoot.appendingPathComponent("docs/construction-universe.tsv")
    }

    /// The sibling's copy, when the sibling is checked out and carries one. A sibling on a
    /// revision from before the table existed has none, and that is a skip, not a pass.
    static var linterUniverseTable: URL? {
        guard let root = swiftProjectLintRoot else { return nil }
        let table = root.appendingPathComponent(linterUniverseTablePath)
        return FileManager.default.fileExists(atPath: table.path) ? table : nil
    }

    @Test(
        "This package and SwiftProjectLint carry the same construction-universe table",
        .enabled(if: linterUniverseTable != nil)
    )
    func universeTableMatchesSwiftProjectLint() throws {
        let theirs = try #require(Self.linterUniverseTable, "guarded by .enabled(if:) — unreachable")
        let ownBytes = try Data(contentsOf: Self.ownUniverseTable)
        let theirBytes = try Data(contentsOf: theirs)
        #expect(ownBytes == theirBytes, """
        The two consumers' construction-universe tables differ, so the predicate each asserts \
        over its own copy is no longer pinned to one answer key — equal SEI pins over different \
        universes are one oracle configured two ways. Make the files byte-identical:
          \(Self.ownUniverseTable.path)
          \(theirs.path)
        """)
    }

    /// Where SwiftProjectLint keeps its copy of the shared cases file — amendment E of the shared
    /// spec: the manifest reader's cases and the build order, beside the predicate's table.
    static let linterUniverseCasesPath = "Docs/construction-universe-cases.json"

    /// This package's copy.
    static var ownUniverseCases: URL {
        packageRoot.appendingPathComponent("docs/construction-universe-cases.json")
    }

    /// The sibling's copy, when the sibling is checked out and carries one — absent on a revision
    /// from before amendment E, which is a skip, not a pass.
    static var linterUniverseCases: URL? {
        guard let root = swiftProjectLintRoot else { return nil }
        let cases = root.appendingPathComponent(linterUniverseCasesPath)
        return FileManager.default.fileExists(atPath: cases.path) ? cases : nil
    }

    /// The `.tsv` pins the predicate and nothing else: the two consumers once carried identical
    /// tables while one bounded nested packages and the other took them all, deduplicated a
    /// symlinked file by a different rule, and so built different tables from one root. The cases
    /// file pins the manifest reader that decides the bound and the order the facts are built in;
    /// each repo asserts its implementation over its own copy, and this keeps the copies one.
    @Test(
        "This package and SwiftProjectLint carry the same construction-universe cases",
        .enabled(if: linterUniverseCases != nil)
    )
    func universeCasesMatchSwiftProjectLint() throws {
        let theirs = try #require(Self.linterUniverseCases, "guarded by .enabled(if:) — unreachable")
        let ownBytes = try Data(contentsOf: Self.ownUniverseCases)
        let theirBytes = try Data(contentsOf: theirs)
        #expect(ownBytes == theirBytes, """
        The two consumers' construction-universe cases differ, so each asserts its manifest reader \
        and build order against a different answer key — one root, two universes. Make the files \
        byte-identical:
          \(Self.ownUniverseCases.path)
          \(theirs.path)
        """)
    }

    /// Where SwiftProjectLint keeps the shared closure — the nested-package bound both consumers
    /// run, whose body is the same text in both (the shared spec's amendments 3 and 3b).
    static let linterNestedPackagesPath =
        "Packages/SwiftProjectLintVisitors/Sources/SwiftProjectLintVisitors/ConstructionUniverse+NestedPackages.swift"

    /// This package's copy.
    static var ownNestedPackages: URL {
        packageRoot.appendingPathComponent("Sources/SwiftInferCore/ConstructionUniverse+NestedPackages.swift")
    }

    /// The sibling's copy, when the sibling is checked out and carries one.
    static var linterNestedPackages: URL? {
        guard let root = swiftProjectLintRoot else { return nil }
        let file = root.appendingPathComponent(linterNestedPackagesPath)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// Everything from the `extension ConstructionUniverse {` line on — the file's header doc
    /// comment names its own repo, and the rest is the shared body — less the trailing
    /// `// swiftlint:` directives each repo's own lint configuration needs around it.
    static func sharedBody(of file: URL) throws -> String? {
        let text = try String(contentsOf: file, encoding: .utf8)
        guard let start = text.range(of: "\nextension ConstructionUniverse {") else { return nil }
        var lines = text[start.lowerBound...].components(separatedBy: "\n")
        while let last = lines.last, last.isEmpty || last.hasPrefix("// swiftlint:") { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// The answer keys pin the readers and the order; the closure that combines them — which
    /// directories it follows, what counts as reached, what is doubt — had only prose saying the two
    /// were "word for word" alike, and the follow-up review found three places they were not. So the
    /// body is the same text in both repos, and this keeps it so.
    @Test(
        "This package and SwiftProjectLint run the same nested-package closure, line for line",
        .enabled(if: linterNestedPackages != nil)
    )
    func nestedPackageClosureMatchesSwiftProjectLint() throws {
        let theirs = try #require(Self.linterNestedPackages, "guarded by .enabled(if:) — unreachable")
        let ownBody = try #require(try Self.sharedBody(of: Self.ownNestedPackages), "no extension in our copy")
        let theirBody = try Self.sharedBody(of: theirs)
        #expect(ownBody == theirBody, """
        The two consumers' nested-package closures differ below their header comments, so one root \
        can bound its nested packages two ways. Make everything from `extension ConstructionUniverse {` \
        on the same text:
          \(Self.ownNestedPackages.path)
          \(theirs.path)
        """)
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

        // The construction-universe clauses' own capability: this package's copies must always be
        // readable, and a sibling without one is said, for the same reason as the skip above.
        Self.noteUniverseClauses(linterRoot: linterRoot)
    }
}
