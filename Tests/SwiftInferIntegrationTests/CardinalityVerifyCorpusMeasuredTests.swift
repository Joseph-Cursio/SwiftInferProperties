import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Cycle 136 — the measured proof of the cycle-135 cardinality
/// gate-overrule. Over `Tests/Fixtures/cardinality-verify-corpus/` (three
/// real `@Reducer` reducers), runs `verify-interaction --all --family
/// cardinality` and asserts the three-way split the decision promised:
///
///   - **RouterFeature** — enforces the mutex, all Action cases payload-free
///     → FULL-coverage `measured-bothPass` → the Finding-G pin is OVERRULED
///     → discover promotes it `.possible → .verified` with the overrule
///     disclosure.
///   - **DrawerFeature** — enforces the mutex too (also `bothPass`), but its
///     Action carries a non-constructible `received(Data)` case → PARTIAL
///     coverage (`excludedActionCount == 1`) → the pin is NOT overruled →
///     stays `.possible`. The coverage gate, not the bothPass, decides.
///   - **LeakyFeature** — does NOT enforce the mutex (the cardinality false
///     positive) → `measured-defaultFails` → suppressed.
///
/// Spawns real `swift build`s resolving swift-composable-architecture;
/// tagged `.subprocess`.
@Suite("Cardinality verify corpus — gate-overrule measured proof (cycle 136)", .tags(.subprocess))
struct CardinalityVerifyCorpusMeasuredTests {

    @Test("full-coverage bothPass overrules the pin (→ Verified); partial stays Possible; false positive suppressed")
    func measuredOverruleSplitsThreeWays() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("cardinality-verify-corpus-measured")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "CardinalityVerifyCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let summary = try await VerifyInteractionSurvey.run(
            target: "CardinalityVerifyCorpus",
            familyFilter: "cardinality",
            sequenceCount: 128,
            workingDirectory: root
        )

        #expect(summary.contains("Identities: 3 (--family cardinality)"))
        #expect(summary.contains("2 measured-bothPass"))
        #expect(summary.contains("1 measured-defaultFails"))
        // DrawerFeature discloses its excluded case (partial exploration);
        // Router/Leaky are full coverage and disclose nothing.
        #expect(summary.contains("explored 3 of 4 action types (excluded: received)"))

        // Evidence: 3 records; the coverage field distinguishes full vs
        // partial — the gate the overrule reads.
        let stored = VerifyEvidenceStore.load(startingFrom: root)
        #expect(stored.log.records.count == 3)
        #expect(stored.log.records.filter { $0.outcome == .measuredBothPass }.count == 2)
        #expect(stored.log.records.filter { $0.outcome == .measuredDefaultFails }.count == 1)
        let bothPass = stored.log.records.filter { $0.outcome == .measuredBothPass }
        // One full-coverage (0 excluded) bothPass and one partial (1 excluded).
        #expect(bothPass.contains { $0.excludedActionCount == 0 })
        #expect(bothPass.contains { $0.excludedActionCount == 1 })

        // Payoff: discover folds the evidence through the cycle-135 overrule.
        let discovered = try SwiftInferCommand.DiscoverInteraction.runPipeline(
            target: "CardinalityVerifyCorpus",
            includePossible: true,
            workingDirectory: root
        )
        // RouterFeature: full-coverage bothPass overrules the pin → Verified,
        // with the disclosure.
        #expect(discovered.contains("(Verified)"))
        #expect(discovered.contains("isShowingSheet"))
        #expect(discovered.contains("Finding-G pin overruled by full-coverage measured execution"))
        // DrawerFeature: partial bothPass → stays Possible (not promoted).
        #expect(discovered.contains("(Possible)"))
        #expect(discovered.contains("isShowingMenu"))
        // LeakyFeature: defaultFails → suppressed (its flags absent).
        #expect(!discovered.contains("isShowingBanner"))
    }

    /// `Tests/Fixtures/cardinality-verify-corpus/`, resolved against
    /// `#filePath` (this target can't see the CLI-test locator).
    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("cardinality-verify-corpus")
    }()
}
