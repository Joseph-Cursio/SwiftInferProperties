import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// M3 (multi-module measured verify) — the headline: `verify-interaction --all`
/// over MULTIPLE `--target`s (modules) verifies reducers from different modules
/// in one run, each built against *its own* library product. The corpus is one
/// SwiftPM package with two library products (Alpha, Beta), each holding a
/// distinct plain-Swift reducer with a module-local helper — so if the survey
/// resolved the wrong module's product, that reducer's build would fail (the
/// symbols wouldn't exist). Two determinism identities → two `measured-bothPass`
/// proves per-module product resolution works end-to-end.
///
/// Dependency-free (no CA) — a light `.subprocess` build. No toolchain gate.
@Suite("Multi-module verify — measured survey (M3)", .tags(.subprocess))
struct MultiModuleVerifyMeasuredTests {

    @Test("survey over Alpha + Beta verifies each against its own module's product")
    func multiModuleSurveyVerifies() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("multi-module-verify-measured")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.packageMultiModule(
            packageName: "MultiModuleVerifyCorpus",
            modules: [
                ("Alpha", Self.moduleDirectory("Alpha")),
                ("Beta", Self.moduleDirectory("Beta"))
            ],
            into: parent
        )

        let summary = try await VerifyInteractionSurvey.run(
            targets: ["Alpha", "Beta"],
            familyFilter: "determinism",
            sequenceCount: 64,
            workingDirectory: root
        )
        // One determinism identity per module, both verified against their own
        // product — a wrong-product build would have failed the reducer.
        #expect(summary.contains("Identities: 2 (--family determinism)"))
        #expect(summary.contains("2 measured-bothPass"))

        let evidence = VerifyEvidenceStore.load(startingFrom: root).log.records
        #expect(evidence.count == 2)
        #expect(evidence.allSatisfy { $0.outcome == .measuredBothPass })

        // discover surfaces each module's identity as Verified (evidence joins
        // by identity hash, so single-target discover per module suffices).
        for (module, reducer) in [("Alpha", "AlphaCounter.reduce"), ("Beta", "BetaCounter.reduce")] {
            let discovered = try SwiftInferCommand.DiscoverInteraction.runPipeline(
                target: module,
                includePossible: true,
                workingDirectory: root
            )
            let block = discovered
                .components(separatedBy: "[Interaction-Invariant Suggestion]")
                .first { $0.contains("Family:    determinism") && $0.contains(reducer) }
            #expect(block?.contains("(Verified)") == true)
        }
    }

    static func moduleDirectory(_ module: String) -> URL {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("multi-module-verify-corpus")
            .appendingPathComponent(module)
    }
}
