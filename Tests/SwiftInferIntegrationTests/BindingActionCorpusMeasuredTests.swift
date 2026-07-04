import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Item 2 slice 4 — `BindingAction<State>` payloads, measured. The
/// `tca-binding-action-corpus`'s `Settings` reducer carries
/// `case binding(BindingAction<State>)` over an `@ObservableState` State; the
/// verifier explores `Action.binding(.set(\.field, <canned value>))` for each
/// defaultable field (String / Bool / Double / Int). A `measured-bothPass`
/// proves the emitted `.set(\.field, value)` compiles against CA and drives a
/// deterministic transition through `BindingReducer` — unlike slice 3b's no-op,
/// this exercises the binding path.
///
/// Real `swift build` against ComposableArchitecture — tagged `.subprocess`.
///
/// ⚠️ TOOLCHAIN NOTE. Runs under **Swift 6.3.3** only (Swift 6.2.4 has a
/// `swift-frontend` bug that crashes before the stub is reached — upstream of
/// this feature). Run under 6.3.3+ (e.g. `swiftly use 6.3.3`). See
/// `docs/tca-determinism-followups.md`.
@Suite("TCA binding-action corpus — BindingAction payload measured", .tags(.subprocess))
struct BindingActionCorpusMeasuredTests {

    @Test("a reducer with a binding(BindingAction<State>) action verifies (bothPass)")
    func bindingActionPayloadVerifies() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("tca-binding-action-corpus-measured")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "TCABindingActionCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let summary = try await VerifyInteractionSurvey.run(
            target: "TCABindingActionCorpus",
            familyFilter: "determinism",
            sequenceCount: 64,
            workingDirectory: root
        )
        #expect(summary.contains("Identities: 1 (--family determinism)"))
        #expect(summary.contains("1 measured-bothPass"))

        let evidence = VerifyEvidenceStore.load(startingFrom: root).log.records
        #expect(evidence.count == 1)
        #expect(evidence.allSatisfy { $0.outcome == .measuredBothPass })

        let discovered = try SwiftInferCommand.DiscoverInteraction.runPipeline(
            target: "TCABindingActionCorpus",
            includePossible: true,
            workingDirectory: root
        )
        let block = discovered
            .components(separatedBy: "[Interaction-Invariant Suggestion]")
            .first { $0.contains("Family:    determinism") && $0.contains("Settings") }
        #expect(block?.contains("(Verified)") == true)
        // Slice-4 payoff: the binding case is explored (full coverage), so no
        // partial-exploration `excluded: binding` disclosure.
        #expect(block?.contains("excluded: binding") != true)
    }

    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("tca-binding-action-corpus")
    }()
}
