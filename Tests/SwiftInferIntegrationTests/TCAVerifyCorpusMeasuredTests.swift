import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// C2 (cycle 127) — the verify-ready REAL-TCA corpus survey. Packages
/// `Tests/Fixtures/tca-verify-corpus/` (real `@Reducer` + `@ObservableState`
/// reducers, self-contained) and runs the measured `--all` survey through
/// the **real witness detector** + the Phase A/B `.tca` verify path —
/// the corpus-curation answer to Phase C (cycle 126). Spawns real
/// `swift build`s resolving swift-composable-architecture; tagged
/// `.subprocess`.
@Suite("TCA verify-ready corpus — C2 measured survey", .tags(.subprocess))
struct TCAVerifyCorpusMeasuredTests {

    @Test("real @Reducer corpus surveys idempotence end-to-end via the detector")
    func surveysRealTCACorpus() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("tca-verify-corpus")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "TCAVerifyCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let summary = try await VerifyInteractionSurvey.run(
            target: "TCAVerifyCorpus",
            familyFilter: "idempotence",
            workingDirectory: root
        )

        // The real witness detector surfaces 5 idempotence identities across
        // the two real @Reducer reducers (NavFeature: dismiss/close/hide;
        // EditorFeature: close/setBadge) and measured verify splits them.
        #expect(summary.contains("Identities: 5 (--family idempotence)"))
        #expect(summary.contains("Summary: 4 measured-bothPass, 1 measured-defaultFails"))
        // The deliberate set* false positive is disproven by execution.
        #expect(summary.contains("[measured-defaultFails]            EditorFeature.body"))
        #expect(summary.contains(".setBadge"))
        // Phase B: EditorFeature's mixed Action discloses the excluded case
        // on every verdict; NavFeature's all-payload-free Action does not
        // (full exploration — no caveat).
        #expect(summary.contains("explored 4 of 5 action types (excluded: received)"))
        let lines = summary.split(separator: "\n")
        #expect(lines.filter { $0.contains("EditorFeature.body") }
            .allSatisfy { $0.contains("partial exploration") })
        #expect(lines.filter { $0.contains("NavFeature.body") }
            .allSatisfy { !$0.contains("partial") })

        // Evidence harvested for all 5; 4 bothPass survive.
        let stored = VerifyEvidenceStore.load(startingFrom: root)
        #expect(stored.log.records.count == 5)
        #expect(stored.log.records.filter { $0.outcome == .measuredBothPass }.count == 4)
        #expect(stored.log.records.filter { $0.outcome == .measuredDefaultFails }.count == 1)

        // Payoff: discover reads the evidence — the 4 survivors render
        // Verified (AST-only, no extra build); setBadge is suppressed.
        let discovered = try SwiftInferCommand.DiscoverInteraction.runPipeline(
            target: "TCAVerifyCorpus",
            workingDirectory: root
        )
        #expect(discovered.contains("(Verified)"))
    }

    /// `Tests/Fixtures/tca-verify-corpus/`, resolved against `#filePath`.
    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("tca-verify-corpus")
    }()
}
