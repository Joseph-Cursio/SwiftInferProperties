import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Phase 2 — measured baseline for **dependency-pinned TCA determinism**, the
/// piece that brings determinism to the carrier 100% of real reducers use.
///
/// The verifier runs each application inside `withDependencies { … }` with the
/// declared @Dependencies pinned to constants, then asserts
/// `reduce(s, a) == reduce(s, a)`. The three-way corpus
/// (`Tests/Fixtures/tca-determinism-corpus/`) proves the thesis — pinned
/// declared dependencies are fine; only UN-declared nondeterminism fails:
///   - `PureCounterFeature` — pure → bothPass → verified;
///   - `ProperDependencyFeature` — `@Dependency(\.uuid)` (pinned) → bothPass →
///     verified (declared dependencies don't fail);
///   - `SnuckRawFeature` — a raw `UUID()` bypassing @Dependency → defaultFails
///     → suppressed (the TCA anti-pattern this catches).
///
/// Real `swift build` against ComposableArchitecture — tagged `.subprocess`.
///
/// ⚠️ TOOLCHAIN NOTE. Verified green under **Swift 6.3.3** (2 bothPass + 1
/// defaultFails, ~66s) — this confirms the emitted `withDependencies` stub
/// compiles against CA and that `@Dependency` resolves inside the pinned scope
/// (`ProperDependencyFeature` promotes to Verified). It does **not** run under
/// **Swift 6.2.4**: that toolchain has a compiler bug (`swift-frontend`
/// SIGABRT type-checking CA's `_alert` deprecation shim), so the synthesized
/// TCA verify workdir's `swift build` deadlocks inside ComposableArchitecture
/// before the stub is reached. The fault is entirely upstream of this feature
/// (any TCA measured-verify build hits it under 6.2.4). Run TCA measured tests
/// under 6.3.3+ — e.g. `swiftly use 6.3.3`.
@Suite("TCA determinism corpus — dependency-pinned measured baseline", .tags(.subprocess))
struct TCADeterminismCorpusMeasuredTests {

    @Test("pinned declared deps pass; a snuck raw UUID() fails — 2 bothPass + 1 defaultFails")
    func dependencyPinnedDeterminismSplits() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("tca-determinism-corpus-measured")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "TCADeterminismCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let summary = try await VerifyInteractionSurvey.run(
            target: "TCADeterminismCorpus",
            familyFilter: "determinism",
            sequenceCount: 64,
            workingDirectory: root
        )
        #expect(summary.contains("Identities: 3 (--family determinism)"))
        #expect(summary.contains("2 measured-bothPass"))
        #expect(summary.contains("1 measured-defaultFails"))

        let evidence = VerifyEvidenceStore.load(startingFrom: root).log.records
        #expect(evidence.count == 3)
        #expect(evidence.filter { $0.outcome == .measuredBothPass }.count == 2)
        #expect(evidence.filter { $0.outcome == .measuredDefaultFails }.count == 1)

        let discovered = try SwiftInferCommand.DiscoverInteraction.runPipeline(
            target: "TCADeterminismCorpus",
            includePossible: true,
            workingDirectory: root
        )
        let blocks = discovered.components(separatedBy: "[Interaction-Invariant Suggestion]")
        func determinismBlock(reducer: String) -> String? {
            blocks.first {
                $0.contains("Family:    determinism") && $0.contains(reducer)
            }
        }
        // Pure and properly-dependency-scoped reducers promote to Verified;
        // the snuck-raw reducer is suppressed (defaultFails) and hidden.
        #expect(determinismBlock(reducer: "PureCounterFeature")?.contains("(Verified)") == true)
        #expect(determinismBlock(reducer: "ProperDependencyFeature")?.contains("(Verified)") == true)
        #expect(determinismBlock(reducer: "SnuckRawFeature") == nil)
    }

    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("tca-determinism-corpus")
    }()
}
