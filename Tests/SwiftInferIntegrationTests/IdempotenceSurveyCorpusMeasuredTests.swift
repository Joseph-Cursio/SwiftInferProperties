import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Cycle 115 — the first *measured idempotence baseline* over the curated
/// verify-ready corpus (`Tests/Fixtures/idempotence-survey-corpus/`).
/// Packages the corpus, runs `verify-interaction --all --family idempotence`,
/// and asserts the measured split:
///   - the 7 genuinely-idempotent identities → `measured-bothPass` →
///     `discover-interaction` promotes each to `.verified`;
///   - the 1 deliberate `set*` false positive (`SettingsReducer.setBadge`)
///     → `measured-defaultFails` → suppressed, NOT promoted.
///
/// This is the campaign payoff: promotion gated on *execution*, with
/// execution catching a name-based false positive the static detector
/// could not. Real `swift build` + runs across three reducers (tens of
/// seconds) — tagged `.subprocess`.
@Suite("Idempotence survey corpus — measured baseline", .tags(.subprocess))
struct IdempotenceSurveyCorpusMeasuredTests {

    @Test("survey records 7 bothPass + 1 defaultFails; discover promotes only the survivors")
    func measuredBaselineSplitsAndPromotes() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("idempotence-survey-corpus-measured")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "IdempotenceSurveyCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        // A trimmed sequence budget keeps each verifier run brief — the
        // build dominates, and the non-idempotent identity traps on the
        // very first sequence regardless.
        let summary = try VerifyInteractionSurvey.run(
            target: "IdempotenceSurveyCorpus",
            familyFilter: "idempotence",
            sequenceCount: 128,
            workingDirectory: root
        )

        #expect(summary.contains("Identities: 8 (--family idempotence)"))
        #expect(summary.contains("7 measured-bothPass"))
        #expect(summary.contains("1 measured-defaultFails"))

        // Evidence harvested for all 8: 7 bothPass, 1 defaultFails.
        let evidence = VerifyEvidenceStore.load(startingFrom: root).log.records
        #expect(evidence.count == 8)
        #expect(evidence.filter { $0.outcome == .measuredBothPass }.count == 7)
        #expect(evidence.filter { $0.outcome == .measuredDefaultFails }.count == 1)

        // Payoff: discover reads the evidence — survivors Verified, the
        // false positive suppressed (absent from the stream).
        let discovered = try SwiftInferCommand.DiscoverInteraction.runPipeline(
            target: "IdempotenceSurveyCorpus",
            includePossible: true,
            workingDirectory: root
        )
        #expect(discovered.contains("(Verified)"))
        #expect(!discovered.contains(".setBadge"))      // defaultFails → suppressed
        #expect(!discovered.contains("(Likely)"))       // every survivor promoted past .likely
    }

    /// `Tests/Fixtures/idempotence-survey-corpus/`, resolved against
    /// `#filePath` (this target can't see the CLI-test locator).
    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("idempotence-survey-corpus")
    }()
}
