import Foundation
import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Guards the isolation gate added 2026-08-13 after `scaffold-kit-suites` emitted 64 laws
/// live against a `.defaultIsolation(MainActor.self)` target and 0 of them compiled
/// (`docs/measurements/exploratory-swiftformatrulestudio.md` §2).
///
/// **The can't-answer arms are the ones that matter.** This gate blocks EVERY carrier when it
/// fires, so a reader who cannot be told why sees a total coverage gap. A bug that made an
/// unreadable manifest answer `"MainActor"` would empty the emitted file for every package in
/// the world, and it would look exactly like a package that legitimately has the setting.
/// Hence the negative arms outnumber the positive one here, deliberately.
@Suite("Target isolation gate — scaffold-kit-suites")
struct TargetIsolationGateTests {

    // MARK: - The gate itself

    @Test("MainActor default isolation blocks, and the reason names the setting and the fix")
    func mainActorBlocks() throws {
        let unwrapped = try #require(KitSuiteEmitter.isolationBlocked("MainActor"))
        #expect(unwrapped.contains(".defaultIsolation(MainActor.self)"))
        #expect(unwrapped.contains("Value: Sendable"))
        // The remedy has to be in the text: a block whose reason states only the cause leaves
        // the reader with a diagnosis and no action.
        #expect(unwrapped.contains("nonisolated"))
        // And the honest limit — this gate hides the per-carrier gates behind it.
        #expect(unwrapped.contains("re-run"))
    }

    @Test("an isolation this code has never heard of still blocks, and is named verbatim")
    func unknownIsolationBlocks() throws {
        // The set of legal values is SwiftPM's to grow. Blocking on an unrecognised one is the
        // safe direction, and echoing it back is what lets a reader act on a value we do not
        // model.
        let reason = try #require(
            KitSuiteEmitter.isolationBlocked("SomeFutureGlobalActor")
        )
        #expect(reason.contains("SomeFutureGlobalActor"))
    }

    @Test("nil — no setting, or an unreadable manifest — does NOT block")
    func nilDoesNotBlock() {
        // The load-bearing arm. `TargetIsolation` collapses "no manifest", "dump-package
        // failed", "JSON drift", "no such target" and "the target sets none" all to nil, and
        // every one of them must emit exactly as before the gate existed.
        #expect(KitSuiteEmitter.isolationBlocked(nil) == nil)
    }

    @Test("an explicitly nonisolated target does NOT block")
    func nonisolatedDoesNotBlock() {
        #expect(KitSuiteEmitter.isolationBlocked("nonisolated") == nil)
    }

    // MARK: - Manifest reading

    @Test("reads the scanned target's own setting, not another target's")
    func readsPerTarget() throws {
        // Per-target and not package-wide: `dump-package` reports the setting on each target,
        // and a package may set it on some and not others. Reading the wrong target's value
        // would block a clean target or clear a dirty one.
        let root = try Self.makePackage(
            named: "Mixed",
            targets: [("Isolated", "MainActor"), ("Plain", nil)]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(
            TargetIsolation.defaultIsolation(packageRoot: root, targetName: "Isolated")
                == "MainActor"
        )
        #expect(TargetIsolation.defaultIsolation(packageRoot: root, targetName: "Plain") == nil)
    }

    @Test("a target the manifest does not declare answers nil rather than guessing")
    func unknownTargetIsNil() throws {
        let root = try Self.makePackage(named: "Mixed", targets: [("Isolated", "MainActor")])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(TargetIsolation.defaultIsolation(packageRoot: root, targetName: "Nope") == nil)
    }

    @Test("no manifest at all answers nil without shelling out")
    func noManifestIsNil() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("iso-none-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(TargetIsolation.defaultIsolation(packageRoot: root, targetName: "X") == nil)
    }

    @Test("an unparseable manifest answers nil, never an isolation")
    func brokenManifestIsNil() throws {
        // The arm that would be catastrophic inverted. `dump-package` exits non-zero here, so
        // this asserts the failure path resolves to "emit as before" and not to "block
        // everything".
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("iso-broken-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "this is not a package manifest".write(
            to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
        )
        #expect(TargetIsolation.defaultIsolation(packageRoot: root, targetName: "X") == nil)
    }

    @Test("packageRoot walks up to the nearest manifest, and answers nil when there is none")
    func packageRootWalk() throws {
        let root = try Self.makePackage(named: "Walk", targets: [("Walk", "MainActor")])
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("Sources/Walk/Deep/Deeper")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        #expect(
            TargetIsolation.packageRoot(containing: nested)?.standardizedFileURL
                == root.standardizedFileURL
        )
        #expect(TargetIsolation.packageRoot(containing: URL(fileURLWithPath: "/")) == nil)
    }

    // MARK: - End to end through the emitter

    @Test("the gate reaches classify: same carrier, live without isolation, blocked with it")
    func classifyRespectsIsolation() {
        // A/B on one variable. Both arms use the same finding, shape and suites, so a
        // difference can only come from the isolation argument.
        let finding = ProtocolCoverageAudit.Finding(
            typeName: "Money",
            coveringConformance: "Equatable",
            standing: .assumed,
            coveredLaws: [.equatableReflexive],
            declaredCoveringConformances: ["Equatable"]
        )
        let shape = TypeShape(
            name: "Money", kind: .struct, inheritedTypes: ["Equatable"], hasUserGen: false,
            storedMembers: [StoredMember(name: "amount", typeName: "Int")]
        )

        let live = KitSuiteEmitter.classify(
            finding: finding, shape: shape, suites: ["Equatable"],
            resolve: { _ in nil }, genericParametersByName: [:], defaultIsolation: nil
        )
        guard case .live = live else {
            Issue.record("control arm must be live, or the A/B proves nothing")
            return
        }

        let blocked = KitSuiteEmitter.classify(
            finding: finding, shape: shape, suites: ["Equatable"],
            resolve: { _ in nil }, genericParametersByName: [:], defaultIsolation: "MainActor"
        )
        guard case .blocked(let text) = blocked else {
            Issue.record("MainActor isolation must block this carrier")
            return
        }
        #expect(text.contains("defaultIsolation"))
    }

    @Test("blocked laws are COUNTED, so the summary cannot report a coverage gap as zero")
    func blockedLawsAreCounted() {
        // The defect was a count, not a compile error: `0 commented out` beside 64 unusable
        // laws. Emitting them commented out while leaving them out of `blockedLaws` would
        // reproduce it exactly, so the count is asserted rather than the text.
        let findings = [
            ProtocolCoverageAudit.Finding(
                typeName: "Money",
                coveringConformance: "Equatable",
                standing: .assumed,
                coveredLaws: [.equatableReflexive, .equatableSymmetric],
                declaredCoveringConformances: ["Equatable"]
            )
        ]
        let shapes = [
            "Money": TypeShape(
                name: "Money", kind: .struct, inheritedTypes: ["Equatable"], hasUserGen: false,
                storedMembers: [StoredMember(name: "amount", typeName: "Int")]
            )
        ]

        let control = KitSuiteEmitter.emit(
            findings: findings, shapes: shapes, moduleName: "M", defaultIsolation: nil
        )
        #expect(control.liveCarriers == 1)
        #expect(control.liveLaws == 2)
        #expect(control.blockedLaws == 0)

        let gated = KitSuiteEmitter.emit(
            findings: findings, shapes: shapes, moduleName: "M", defaultIsolation: "MainActor"
        )
        #expect(gated.liveCarriers == 0)
        #expect(gated.liveLaws == 0)
        #expect(gated.blockedCarriers == 1)
        #expect(gated.blockedLaws == 2)
        // Laws are conserved across the gate — none may be dropped on the floor, which is a
        // third failure mode beside "live but broken" and "blocked but uncounted".
        #expect(control.liveLaws + control.blockedLaws == gated.liveLaws + gated.blockedLaws)
    }

    @Test("the banner no longer attributes every block to an underivable generator")
    func bannerIsCauseNeutral() {
        // It said "commented out: the generator could not be derived" for all four gates. A
        // reader acting on that writes a `gen()` that changes nothing.
        let header = KitSuiteEmitter.header(
            KitSuiteEmitter.Counts(
                liveCarriers: 0, blockedCarriers: 1, liveLaws: 0, blockedLaws: 2
            )
        )
        #expect(!header.contains("commented out: the generator could not be derived"))
        #expect(header.contains("each with its reason"))
    }

    // MARK: - Fixture

    /// A manifest with one target per `(name, isolation)` pair. Written as source and read
    /// back through the real `swift package dump-package`, rather than hand-feeding JSON to
    /// the decoder — the thing under test is whether we can read what SwiftPM actually emits,
    /// and a hand-written fixture would pass even if that shape drifted.
    static func makePackage(
        named name: String,
        targets: [(String, String?)]
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("iso-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let targetDeclarations = targets.map { targetName, isolation in
            // The comma is load-bearing and its absence is why this fixture failed first time:
            // the manifest did not parse, `dump-package` exited non-zero, and
            // `defaultIsolation` answered nil — which is the CORRECT degradation and therefore
            // indistinguishable from a target that simply sets nothing. A fixture bug reading
            // as a clean pass is the reason `readsPerTarget` asserts the positive value rather
            // than only asserting that the two targets differ.
            let settings = isolation.map {
                ",\n            swiftSettings: [.defaultIsolation(\($0).self)]"
            } ?? ""
            return "        .target(\n            name: \"\(targetName)\"\(settings)\n        )"
        }
        .joined(separator: ",\n")

        for (targetName, _) in targets {
            let sources = root.appendingPathComponent("Sources/\(targetName)")
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try "public struct Placeholder { public init() {} }".write(
                to: sources.appendingPathComponent("Placeholder.swift"),
                atomically: true, encoding: .utf8
            )
        }

        try """
        // swift-tools-version: 6.2
        import PackageDescription

        let package = Package(
            name: "\(name)",
            targets: [
        \(targetDeclarations)
            ]
        )
        """.write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        return root
    }
}
