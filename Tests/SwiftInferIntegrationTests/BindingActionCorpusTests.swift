import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Item 2 slice 4 — fast (no-subprocess) proof that discovery → resolve → emit
/// constructs a `BindingAction.set(\.field, value)` value against the real
/// `tca-binding-action-corpus`. `resolveAndEmit` is pure (no `swift build`), so
/// this runs in the fast path and pins the emitted expression without the ~60s
/// measured build.
@Suite("TCA binding-action corpus — resolve + emit (slice 4)")
struct BindingActionCorpusTests {

    @Test("Settings' binding(BindingAction<State>) resolves to .set over every defaultable field")
    func resolvesAndEmitsBinding() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("tca-binding-action-corpus-resolve")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "TCABindingActionCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let (candidate, stub) = try VerifyInteractionPipeline.resolveAndEmit(
            target: "TCABindingActionCorpus",
            pinRaw: "Settings.body",
            workingDirectory: root
        )
        #expect(candidate.qualifiedName == "Settings.body")

        // Each defaultable field is bound with its canned literal.
        #expect(stub.contains("Settings.Action.binding(.set(\\.displayName, \"\"))"))
        #expect(stub.contains("Settings.Action.binding(.set(\\.notificationsEnabled, false))"))
        #expect(stub.contains("Settings.Action.binding(.set(\\.fontScale, 0.0))"))
        #expect(stub.contains("Settings.Action.binding(.set(\\.retryCount, 0))"))

        // Slice-4 payoff: `binding` is now explored (constructible), not excluded.
        let binding = candidate.actionCases.first { $0.name == "binding" }
        #expect(binding?.resolvedBinding?.count == 4)
        #expect(ActionSequenceStubEmitter.excludedCaseNames(candidate).contains("binding") == false)
    }

    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("tca-binding-action-corpus")
    }()
}
