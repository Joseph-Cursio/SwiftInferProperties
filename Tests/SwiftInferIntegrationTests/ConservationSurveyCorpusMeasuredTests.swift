import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Cycle 134 — the *first measured baseline for a second interaction
/// family*. The measured-verify path (per-step `precondition(<predicate>)`
/// in the generated stub + the family-generic `InteractionVerifyEvidence
/// Scoring` fold) was already wired for all five families; idempotence was
/// merely the only one ever demonstrated end-to-end. This proves it on
/// **conservation** — the cleanest non-idempotence shape: a State-only
/// predicate, un-gated (no `swiftProjectLintDeferral`), no `Identifiable`
/// friction.
///
/// Over the curated verify-ready corpus
/// (`Tests/Fixtures/conservation-survey-corpus/`), runs
/// `verify-interaction --all --family conservation` and asserts the split:
///   - `InventoryReducer` keeps `count == items.count` across every
///     action → `measured-bothPass` → `discover-interaction` promotes it
///     `.possible → .verified` (score 30 + 50 = 80 → `.strong` → promoted);
///   - the deliberate false positive `BadgeReducer` (badgeCount drifts
///     ahead of notifications) → `measured-defaultFails` → suppressed, NOT
///     promoted.
///
/// The campaign thesis, now on a second family: promotion gated on
/// *execution*, with execution catching a name-shaped false positive the
/// static detector cannot. Real `swift build` + runs — tagged
/// `.subprocess`.
@Suite("Conservation survey corpus — measured baseline (cycle 134)", .tags(.subprocess))
struct ConservationSurveyCorpusMeasuredTests {

    @Test("survey records 1 bothPass + 1 defaultFails; discover promotes only the conserving reducer")
    func measuredBaselineSplitsAndPromotes() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("conservation-survey-corpus-measured")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "ConservationSurveyCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let summary = try await VerifyInteractionSurvey.run(
            target: "ConservationSurveyCorpus",
            familyFilter: "conservation",
            sequenceCount: 128,
            workingDirectory: root
        )

        #expect(summary.contains("Identities: 2 (--family conservation)"))
        #expect(summary.contains("1 measured-bothPass"))
        #expect(summary.contains("1 measured-defaultFails"))

        // Evidence harvested for both identities.
        let evidence = VerifyEvidenceStore.load(startingFrom: root).log.records
        #expect(evidence.count == 2)
        #expect(evidence.filter { $0.outcome == .measuredBothPass }.count == 1)
        #expect(evidence.filter { $0.outcome == .measuredDefaultFails }.count == 1)

        // Payoff: discover reads the evidence — the conserving reducer is
        // promoted past .possible to Verified; the false positive is
        // suppressed (its predicate absent from the stream).
        let discovered = try SwiftInferCommand.DiscoverInteraction.runPipeline(
            target: "ConservationSurveyCorpus",
            includePossible: true,
            workingDirectory: root
        )
        #expect(discovered.contains("(Verified)"))
        #expect(discovered.contains("state.count == state.items.count"))   // Inventory survives
        #expect(!discovered.contains("state.badgeCount"))                  // Badge suppressed
        #expect(!discovered.contains("(Possible)"))                        // survivor promoted off .possible
    }

    /// `Tests/Fixtures/conservation-survey-corpus/`, resolved against
    /// `#filePath` (this target can't see the CLI-test locator).
    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("conservation-survey-corpus")
    }()
}
