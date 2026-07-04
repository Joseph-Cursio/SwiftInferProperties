import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Tier-2 measured baseline over **real, curated Point-Free TCA reducers** —
/// the highest-fidelity proof that dependency-pinned determinism measured-verify
/// compiles and runs on idiomatic TCA, not just synthetic fixtures. Companion to
/// `TCADeterminismCorpusMeasuredTests` (which uses hand-crafted three-way
/// reducers); this one uses reducers lifted verbatim from TCA's own `Examples/`
/// tree, View scaffolding stripped (`Tests/Fixtures/tca-examples-measured-corpus/`,
/// see its ATTRIBUTION.md).
///
/// All three are clean Point-Free code, so all three should measure bothPass and
/// promote to Verified:
///   - `Counter` — pure;
///   - `OptionalBasics` — pure, composes `Counter` via `.ifLet`;
///   - `Timers` — one CA built-in dependency (`\.continuousClock`), pinned by the
///     verifier → a declared/pinned dependency is fine → bothPass.
///
/// Real `swift build` against ComposableArchitecture — tagged `.subprocess`.
///
/// ⚠️ TOOLCHAIN NOTE. Runs under **Swift 6.3.3** only. Swift 6.2.4 has a
/// compiler bug (`swift-frontend` SIGABRT type-checking CA's `_alert`
/// deprecation shim) that deadlocks any TCA measured-verify build before the
/// stub is reached — entirely upstream of this feature. Run under 6.3.3+ (e.g.
/// `swiftly use 6.3.3`). See `docs/tca-determinism-followups.md` item 4.
@Suite("TCA examples measured corpus — real reducers, dependency-pinned determinism", .tags(.subprocess))
struct TCAExamplesMeasuredTests {

    @Test("real curated TCA reducers compile and measure determinism — 3 bothPass, 0 defaultFails")
    func realReducersDeterminismAllPass() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("tca-examples-measured-corpus")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "TCAExamplesCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let summary = try await VerifyInteractionSurvey.run(
            target: "TCAExamplesCorpus",
            familyFilter: "determinism",
            sequenceCount: 64,
            workingDirectory: root
        )
        #expect(summary.contains("Identities: 3 (--family determinism)"))
        #expect(summary.contains("3 measured-bothPass"))

        let evidence = VerifyEvidenceStore.load(startingFrom: root).log.records
        #expect(evidence.count == 3)
        #expect(evidence.filter { $0.outcome == .measuredBothPass }.count == 3)
        #expect(evidence.filter { $0.outcome == .measuredDefaultFails }.isEmpty)

        let discovered = try SwiftInferCommand.DiscoverInteraction.runPipeline(
            target: "TCAExamplesCorpus",
            includePossible: true,
            workingDirectory: root
        )
        let blocks = discovered.components(separatedBy: "[Interaction-Invariant Suggestion]")
        func determinismBlock(reducer: String) -> String? {
            blocks.first {
                $0.contains("Family:    determinism") && $0.contains(reducer)
            }
        }
        #expect(determinismBlock(reducer: "Counter")?.contains("(Verified)") == true)
        #expect(determinismBlock(reducer: "OptionalBasics")?.contains("(Verified)") == true)
        #expect(determinismBlock(reducer: "Timers")?.contains("(Verified)") == true)
    }

    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("tca-examples-measured-corpus")
    }()
}
