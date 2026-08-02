import Foundation
import PropertyLawKit
import SwiftInferCore
@testable import SwiftInferKitEvidence
import Testing

/// **Does the kit feedback loop actually close?**
///
/// It did not until 2026-08-02. `KitEvidenceStore.load` was wired into `discover`,
/// `KitEvidenceStore.write` had zero callers anywhere in `Sources` or `Tests`, no subcommand
/// exported anything, and PropertyLawKit has never heard of `kit-evidence.json`. The `-45`
/// demotion for a refuted equality oracle had never fired on any project and could not.
///
/// So the load-bearing test here is the **round trip through a real kit run**: kit produces
/// `[CheckResult]` → recorder writes → store loads → the querying API that inference calls
/// answers correctly. Unit-testing the translation alone would have passed just as happily
/// while the law names silently failed to match.
@Suite("Kit evidence — the write half of the loop")
struct KitEvidenceRecorderTests {

    struct Money: Equatable, Hashable {
        let amount: Int
    }

    private static func moneyGen() -> Generator<Money, some SendableSequenceType> {
        Gen<Int>.int(in: 0...500).map { Money(amount: $0) }
    }

    private static func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KitEvidenceRecorder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // `KitEvidenceStore.load` walks up looking for `Package.swift` or `.swiftinfer/`.
        // Without a marker the walk escapes into the real filesystem and finds someone
        // else's package — which is how a green test can be reading the wrong file.
        try "// marker".write(
            to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
        )
        return root
    }

    // MARK: - The round trip that proves the loop is closed

    @Test("a real kit run reaches `discover`'s reader intact")
    func realKitRunRoundTrips() async throws {
        let root = try Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let results = try await checkEquatablePropertyLaws(
            for: Money.self,
            using: Self.moneyGen(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(!results.isEmpty, "the suite must actually run laws")

        try KitEvidenceRecorder.record(results, for: "Money", packageRoot: root)

        let loaded = KitEvidenceStore.load(startingFrom: root)
        #expect(loaded.wasExercised("Money"))
        // The point of the exercise: the querying API inference calls must recognise the
        // law names the kit produced. `equalityOracleLaws` matches on exact qualified names,
        // so this fails if `protocolLaw`'s format and that set ever diverge.
        #expect(loaded.confirmedEqualityOracle(for: "Money"))
        #expect(loaded.refutedEqualityOracle(for: "Money") == nil, "a correct type")
    }

    /// The kit throws on a Strict violation under `EnforcementMode.default`, so a genuinely
    /// refuted run cannot hand back `[CheckResult]` to record. The refutation path is
    /// therefore driven from a constructed result — which is exactly the shape the kit builds.
    @Test("a refuted equality oracle survives the round trip and is queryable")
    func refutedOracleRoundTrips() throws {
        let root = try Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let refuted = CheckResult(
            protocolLaw: "Hashable.equalityConsistency",
            tier: .strict,
            trials: 17,
            seed: Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            environment: Environment(
                swiftVersion: "6.1", backendIdentity: "test", generatorSchemaHash: "x"
            ),
            outcome: .failed(counterexample: "P0/0 vs P0/1")
        )
        try KitEvidenceRecorder.record([refuted], for: "ProjectedPlayerScore", packageRoot: root)

        let loaded = KitEvidenceStore.load(startingFrom: root)
        let found = loaded.refutedEqualityOracle(for: "ProjectedPlayerScore")
        #expect(found != nil, "this is what drives the -45 demotion")
        #expect(found?.law == "Hashable.equalityConsistency")
        #expect(found?.counterexample == "P0/0 vs P0/1")
    }

    // MARK: - Translation

    /// **The silent-failure guard.** `Codable.roundTripFidelity[JSON]` must record as
    /// `Codable.roundTripFidelity`, because `equalityOracleLaws` compares exact qualified
    /// names and `LawIdentifier.matches` strips the suffix for the same reason. An adapter
    /// passing `protocolLaw` through unchanged records laws that never match, and the symptom
    /// is indistinguishable from the kit having passed.
    @Test("the backend suffix is stripped from the law name")
    func backendSuffixStripped() {
        #expect(
            KitEvidenceRecorder.canonicalLawName("Codable.roundTripFidelity[JSON]")
                == "Codable.roundTripFidelity"
        )
        #expect(
            KitEvidenceRecorder.canonicalLawName("Hashable.equalityConsistency")
                == "Hashable.equalityConsistency"
        )
    }

    /// `.expectedViolation` must NOT become `.failed`. The author used the kit's own
    /// `.intentionalViolation` suppression to say the failure is the documented design, and
    /// `refutedEqualityOracle` excludes it deliberately — mapping it to `.failed` would
    /// demote every suggestion about a carrier whose owner documented a known deviation.
    @Test("an intentional violation is not recorded as a refutation")
    func expectedViolationIsNotFailure() {
        let outcome = KitEvidenceRecorder.outcome(
            from: .expectedViolation(reason: "documented", counterexample: "x")
        )
        #expect(outcome == .expectedViolation)
        #expect(outcome != .failed)
    }

    @Test("every kit outcome and tier maps onto the recorded vocabulary")
    func translationIsTotal() {
        #expect(KitEvidenceRecorder.outcome(from: .passed) == .passed)
        #expect(KitEvidenceRecorder.outcome(from: .failed(counterexample: "c")) == .failed)
        #expect(KitEvidenceRecorder.outcome(from: .suppressed(reason: "r")) == .suppressed)
        for strictness in StrictnessTier.allCases {
            // Total by construction — the switch has no default, so a new kit tier is a
            // compile error here rather than a silently mis-recorded row.
            _ = KitEvidenceRecorder.tier(from: strictness)
        }
    }

    // MARK: - Merging

    /// Recording is merge, not replace. A project checks several types across several suites
    /// and each call sees only its own; replacing would leave the last suite to run as the
    /// only one on record. The failure would be silent — a smaller log is still valid and
    /// simply demotes less.
    @Test("recording one carrier preserves another's evidence")
    func recordingMergesAcrossCarriers() throws {
        let root = try Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try KitEvidenceRecorder.record([Self.passing("Equatable.reflexivity")], for: "Alpha", packageRoot: root)
        try KitEvidenceRecorder.record([Self.passing("Equatable.symmetry")], for: "Beta", packageRoot: root)

        let loaded = KitEvidenceStore.load(startingFrom: root)
        #expect(loaded.wasExercised("Alpha"), "the earlier carrier must survive")
        #expect(loaded.wasExercised("Beta"))
    }

    /// …but re-running the same suite replaces that carrier's rows. A stale `failed` from a
    /// previous run must not outlive the fix.
    @Test("re-recording the same carrier replaces its rows")
    func reRecordingReplacesTheCarrier() throws {
        let root = try Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let stale = CheckResult(
            protocolLaw: "Hashable.equalityConsistency",
            tier: .strict,
            trials: 1,
            seed: Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            environment: Environment(
                swiftVersion: "6.1", backendIdentity: "test", generatorSchemaHash: "x"
            ),
            outcome: .failed(counterexample: "old")
        )
        try KitEvidenceRecorder.record([stale], for: "Money", packageRoot: root)
        #expect(KitEvidenceStore.load(startingFrom: root).refutedEqualityOracle(for: "Money") != nil)

        try KitEvidenceRecorder.record([Self.passing("Hashable.equalityConsistency")], for: "Money", packageRoot: root)
        let loaded = KitEvidenceStore.load(startingFrom: root)
        #expect(loaded.refutedEqualityOracle(for: "Money") == nil, "the fix must clear the refutation")
        #expect(loaded.wasExercised("Money"))
    }

    private static func passing(_ law: String) -> CheckResult {
        CheckResult(
            protocolLaw: law,
            tier: .strict,
            trials: 100,
            seed: Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            environment: Environment(
                swiftVersion: "6.1", backendIdentity: "test", generatorSchemaHash: "x"
            ),
            outcome: .passed
        )
    }
}
