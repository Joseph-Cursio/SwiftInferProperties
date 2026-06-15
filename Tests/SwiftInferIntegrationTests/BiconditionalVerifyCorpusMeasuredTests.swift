import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Cycle 137 — the measured proof that the cycle-135/136 gate-overrule is
/// family-generic: biconditional (the *second* `swiftProjectLintDeferral`
/// family) promotes by the same rule cardinality did, with no new mechanism
/// — only this corpus. Over `Tests/Fixtures/biconditional-verify-corpus/`
/// (three real `@Reducer`s), runs `verify-interaction --all --family
/// biconditional` and asserts the same three-way split:
///
///   - **SessionFeature** — keeps `isActive == (token != nil)` in sync, all
///     Action cases payload-free → FULL-coverage `measured-bothPass` → the
///     Finding-G pin is OVERRULED → discover promotes it
///     `.possible → .verified` with the overrule disclosure.
///   - **ConnectionFeature** — keeps the pair in sync too (also `bothPass`),
///     but its Action carries a non-constructible `received(Data)` case →
///     PARTIAL coverage (`excludedActionCount == 1`) → the pin is NOT
///     overruled → stays `.possible`.
///   - **StaleFeature** — drifts the flag ahead of the result (the
///     biconditional false positive) → `measured-defaultFails` → suppressed.
///
/// Spawns real `swift build`s resolving swift-composable-architecture;
/// tagged `.subprocess`.
@Suite("Biconditional verify corpus — gate-overrule measured proof (cycle 137)", .tags(.subprocess))
struct BiconditionalVerifyCorpusMeasuredTests {

    @Test("full-coverage bothPass overrules the pin (→ Verified); partial stays Possible; false positive suppressed")
    func measuredOverruleSplitsThreeWays() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("biconditional-verify-corpus-measured")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "BiconditionalVerifyCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let summary = try await VerifyInteractionSurvey.run(
            target: "BiconditionalVerifyCorpus",
            familyFilter: "biconditional",
            sequenceCount: 128,
            workingDirectory: root
        )

        #expect(summary.contains("Identities: 3 (--family biconditional)"))
        #expect(summary.contains("2 measured-bothPass"))
        #expect(summary.contains("1 measured-defaultFails"))
        // ConnectionFeature discloses its excluded case (partial exploration);
        // Session/Stale are full coverage and disclose nothing.
        #expect(summary.contains("explored 2 of 3 action types (excluded: received)"))

        // Evidence: 3 records; the coverage field distinguishes full vs
        // partial — the gate the overrule reads.
        let stored = VerifyEvidenceStore.load(startingFrom: root)
        #expect(stored.log.records.count == 3)
        #expect(stored.log.records.filter { $0.outcome == .measuredBothPass }.count == 2)
        #expect(stored.log.records.filter { $0.outcome == .measuredDefaultFails }.count == 1)
        let bothPass = stored.log.records.filter { $0.outcome == .measuredBothPass }
        #expect(bothPass.contains { $0.excludedActionCount == 0 })   // SessionFeature
        #expect(bothPass.contains { $0.excludedActionCount == 1 })   // ConnectionFeature

        // Payoff: discover folds the evidence through the cycle-135 overrule.
        let discovered = try SwiftInferCommand.DiscoverInteraction.runPipeline(
            target: "BiconditionalVerifyCorpus",
            includePossible: true,
            workingDirectory: root
        )
        // SessionFeature: full-coverage bothPass overrules the pin → Verified.
        #expect(discovered.contains("(Verified)"))
        #expect(discovered.contains("state.isActive == (state.token != nil)"))
        #expect(discovered.contains("Finding-G pin overruled by full-coverage measured execution"))
        // ConnectionFeature: partial bothPass → stays Possible (not promoted).
        #expect(discovered.contains("(Possible)"))
        #expect(discovered.contains("state.isFetching == (state.payload != nil)"))
        // StaleFeature: defaultFails → suppressed (its predicate absent).
        #expect(!discovered.contains("state.isLoading == (state.data != nil)"))
    }

    /// `Tests/Fixtures/biconditional-verify-corpus/`, resolved against
    /// `#filePath` (this target can't see the CLI-test locator).
    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("biconditional-verify-corpus")
    }()
}
