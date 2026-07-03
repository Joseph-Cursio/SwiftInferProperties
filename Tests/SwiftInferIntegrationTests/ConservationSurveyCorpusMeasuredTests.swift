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

    @Test("survey records 2 bothPass + 2 defaultFails; discover promotes only the conserving reducers")
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

        // Cycle 140 — widened to 4 reducers: InventoryReducer (lockstep) +
        // CartReducer (recompute) conserve → bothPass; BadgeReducer
        // (increment-without-append) + RosterReducer (clear-without-reset)
        // desync → defaultFails.
        #expect(summary.contains("Identities: 4 (--family conservation)"))
        #expect(summary.contains("2 measured-bothPass"))
        #expect(summary.contains("2 measured-defaultFails"))

        // Evidence harvested for all four identities.
        let evidence = VerifyEvidenceStore.load(startingFrom: root).log.records
        #expect(evidence.count == 4)
        #expect(evidence.filter { $0.outcome == .measuredBothPass }.count == 2)
        #expect(evidence.filter { $0.outcome == .measuredDefaultFails }.count == 2)

        // Payoff: discover reads the evidence — the two conserving reducers
        // are promoted past .possible to Verified; both false positives are
        // suppressed (their predicates absent from the stream).
        let discovered = try SwiftInferCommand.DiscoverInteraction.runPipeline(
            target: "ConservationSurveyCorpus",
            includePossible: true,
            workingDirectory: root
        )
        #expect(discovered.contains("(Verified)"))
        #expect(!discovered.contains("state.badgeCount"))                    // Badge suppressed
        #expect(!discovered.contains("state.memberCount"))                   // Roster suppressed
        // The two conserving reducers are promoted off .possible to Verified,
        // asserted per-predicate rather than via a blanket "nothing is
        // Possible": Determinism (Phase 2 Redux) now surfaces one witness-free
        // .possible suggestion per redux reducer in this corpus, and it was NOT
        // part of this conservation-only verify run, so it correctly stays
        // .possible — orthogonal noise for this test.
        let blocks = discovered.components(separatedBy: "[Interaction-Invariant Suggestion]")
        func block(forPredicate needle: String) -> String? {
            blocks.first { $0.contains("Predicate: \(needle)") }
        }
        #expect(block(forPredicate: "state.count == state.items.count")?.contains("(Verified)") == true)
        #expect(block(forPredicate: "state.itemCount == state.lineItems.count")?.contains("(Verified)") == true)
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
