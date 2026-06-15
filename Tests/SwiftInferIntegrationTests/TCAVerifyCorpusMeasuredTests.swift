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
        assertSurvey(summary)

        // Evidence harvested for all 19; 17 bothPass survive.
        let stored = VerifyEvidenceStore.load(startingFrom: root)
        #expect(stored.log.records.count == 19)
        #expect(stored.log.records.filter { $0.outcome == .measuredBothPass }.count == 17)
        #expect(stored.log.records.filter { $0.outcome == .measuredDefaultFails }.count == 2)

        // Payoff: discover reads the evidence — survivors render Verified
        // (AST-only, no extra build); the false positives are suppressed.
        let discovered = try SwiftInferCommand.DiscoverInteraction.runPipeline(
            target: "TCAVerifyCorpus",
            workingDirectory: root
        )
        #expect(discovered.contains("(Verified)"))
    }

    private func assertSurvey(_ summary: String) {
        // The real witness detector surfaces idempotence witnesses across the
        // eleven real @Reducer reducers and measured verify splits them: only
        // the two name-vs-behavior false positives fail — setBadge (set*) and
        // ToggleFeature.hide (exact witness that toggles).
        #expect(summary.contains("Identities: 19 (--family idempotence)"))
        #expect(summary.contains("Summary: 17 measured-bothPass, 2 measured-defaultFails"))
        // The method-reference body form (Reduce(handle)) verifies, and an
        // effect-bearing body (.run) verifies with the Effect discarded.
        #expect(summary.contains("MethodRefFeature.body  idempotence  .dismiss"))
        #expect(summary.contains("EffectFeature.body  idempotence  .refresh"))
        // Cycle 133 — composed bodies verify: a two-Reduce-closure body
        // (the dedup fix; pre-133 this was ambiguousPin/measured-error) and a
        // Scope composition (whole composed body, child action excluded).
        #expect(summary.contains("MultiReduceFeature.body  idempotence  .dismiss"))
        #expect(summary.contains("ChildFeature.body  idempotence  .close"))
        #expect(summary.contains("ParentFeature.body  idempotence  .dismiss"))
        // The deliberate set* false positive is disproven by execution.
        #expect(summary.contains("[measured-defaultFails]            EditorFeature.body"))
        #expect(summary.contains(".setBadge"))
        // A set* TRUE positive (SettingsFeature.setEnabled → enabled = true)
        // verifies bothPass — the mirror of EditorFeature.setBadge's set*
        // FALSE positive; execution distinguishes them.
        #expect(summary.contains("[measured-bothPass]") && summary.contains(".setEnabled"))

        // Phase B: the MIXED reducers (EditorFeature, SettingsFeature)
        // disclose their excluded case on every verdict; the all-payload-free
        // reducers (NavFeature, SelectionFeature) do not (full exploration).
        #expect(summary.contains("explored 4 of 5 action types (excluded: received)"))
        #expect(summary.contains("explored 4 of 5 action types (excluded: sync)"))
        // A richer excluded set — two non-derivable cases in one disclosure.
        #expect(summary.contains("explored 3 of 5 action types (excluded: received, markItems)"))
        let lines = summary.split(separator: "\n")
        // ParentFeature is mixed (child action excluded → "excluded: child").
        #expect(summary.contains("explored 2 of 3 action types (excluded: child)"))
        let mixedExploration = [
            "EditorFeature.body", "SettingsFeature.body", "DownloadFeature.body",
            "ParentFeature.body"
        ]
        for mixed in mixedExploration {
            #expect(lines.filter { $0.contains(mixed) }.allSatisfy { $0.contains("partial") })
        }
        let fullExploration = [
            "NavFeature.body", "SelectionFeature.body", "ToggleFeature.body",
            "MethodRefFeature.body", "EffectFeature.body",
            "MultiReduceFeature.body", "ChildFeature.body"
        ]
        for full in fullExploration {
            #expect(lines.filter { $0.contains(full) }.allSatisfy { !$0.contains("partial") })
        }
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
