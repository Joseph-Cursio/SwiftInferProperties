import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// Split out so the primary `VerifyInteractionPipelineTests` struct body stays
// under SwiftLint's `type_body_length`. `@Test` methods in an extension of the
// `@Suite` type are still discovered as part of the suite, and extension
// bodies are exempt from the rule. The `makeFixtureDirectory` / `writeFile`
// fixture helpers (used only by these resolveAndEmit tests) live at the
// bottom of this extension.
extension VerifyInteractionPipelineTests {

    // MARK: - End-to-end resolveAndEmit against a fixture directory
    //
    // (The full `runPipeline` does subprocess builds and gets an
    // integration test in SwiftInferIntegrationTests, skipped by
    // default. These tests cover the pure leg: discovery + pin
    // resolution + stub emission.)

    @Test("resolveAndEmit against a single-reducer fixture returns the candidate + emitted stub")
    func resolveAndEmitSingleReducer() throws {
        let directory = try makeFixtureDirectory(name: "PipelineSingleReducer")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeFile(
            in: directory,
            relativePath: "Sources/MyApp",
            named: "Inbox.swift",
            contents: "func reduce(_ s: AppState, _ a: AppAction) -> AppState { return s }"
        )
        let (candidate, stubSource) = try VerifyInteractionPipeline.resolveAndEmit(
            target: "MyApp",
            workingDirectory: directory
        )
        #expect(candidate.functionName == "reduce")
        #expect(candidate.carrierKind == .elmStyle)
        #expect(stubSource.contains(ActionSequenceStubEmitter.stubHeaderMarker))
        #expect(stubSource.contains("import MyApp"))
        #expect(stubSource.contains(ActionSequenceStubEmitter.cleanOutcomeMarker))
    }

    @Test("Cycle 133 — resolveAndEmit dedups a composed body (multiple Reduce closures), no ambiguousPin")
    func resolveAndEmitComposedBody() throws {
        let directory = try makeFixtureDirectory(name: "PipelineComposedBody")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeFile(
            in: directory,
            relativePath: "Sources/MyApp",
            named: "Feature.swift",
            contents: """
            import ComposableArchitecture
            @Reducer
            struct Feature {
                struct State: Equatable { var count = 0 }
                enum Action { case close, tick }
                var body: some Reducer<State, Action> {
                    Reduce { state, action in .none }
                    Reduce { state, action in .none }
                }
            }
            """
        )
        // Two Reduce closures → two "Feature.body" candidates; pre-133 this
        // threw ambiguousPin. The (state, action) dedup now resolves it to
        // the one composed reducer.
        let (candidate, stubSource) = try VerifyInteractionPipeline.resolveAndEmit(
            target: "MyApp",
            workingDirectory: directory,
            pinRaw: "Feature.body"
        )
        #expect(candidate.qualifiedName == "Feature.body")
        #expect(candidate.carrierKind == .tca)
        #expect(stubSource.contains("let reducer = Feature()"))
    }

    @Test("resolveAndEmit with no reducers throws noReducersDetected")
    func resolveAndEmitNoReducers() throws {
        let directory = try makeFixtureDirectory(name: "PipelineNoReducers")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeFile(
            in: directory,
            relativePath: "Sources/MyApp",
            named: "Empty.swift",
            contents: "// no reducer here"
        )
        #expect(throws: VerifyInteractionError.noReducersDetected) {
            _ = try VerifyInteractionPipeline.resolveAndEmit(
                target: "MyApp",
                workingDirectory: directory
            )
        }
    }

    @Test("resolveAndEmit with multiple candidates and no pin throws requiresPin")
    func resolveAndEmitMultipleNoPin() throws {
        let directory = try makeFixtureDirectory(name: "PipelineMultipleNoPin")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeFile(
            in: directory,
            relativePath: "Sources/MyApp",
            named: "A.swift",
            contents: "func reduceA(_ s: StateA, _ a: ActionA) -> StateA { return s }"
        )
        try writeFile(
            in: directory,
            relativePath: "Sources/MyApp",
            named: "B.swift",
            contents: "func reduceB(_ s: StateB, _ a: ActionB) -> StateB { return s }"
        )
        do {
            _ = try VerifyInteractionPipeline.resolveAndEmit(
                target: "MyApp",
                workingDirectory: directory
            )
            Issue.record("expected requiresPin error")
        } catch let error as VerifyInteractionError {
            switch error {
            case .requiresPin:
                break

            default:
                Issue.record("expected .requiresPin, got \(error)")
            }
        } catch {
            Issue.record("expected VerifyInteractionError, got \(error)")
        }
    }

    @Test("resolveAndEmit against effect-tuple shape — M8.A emits effect-discard stub")
    func resolveAndEmitEffectTupleShape() throws {
        let directory = try makeFixtureDirectory(name: "PipelineEffectTupleShape")
        defer { try? FileManager.default.removeItem(at: directory) }
        // Body actually references Effect.run (not just .none) so the
        // M8.B purity analyzer classifies the body as .effectBearing
        // alongside the signature-shape match.
        try writeFile(
            in: directory,
            relativePath: "Sources/MyApp",
            named: "Effect.swift",
            contents: """
            func reduce(_ s: AppState, _ a: AppAction) -> (AppState, Effect<AppAction>) {
                return (s, Effect.run { _ in })
            }
            """
        )
        let (candidate, stubSource) = try VerifyInteractionPipeline.resolveAndEmit(
            target: "MyApp",
            workingDirectory: directory
        )
        #expect(candidate.signatureShape == .stateActionReturnsStateAndEffect)
        #expect(candidate.purity == .effectBearing)
        // The effect half is captured into `_` and discarded — PRD §16 #1.
        #expect(stubSource.contains("let (newState, _) = reduce(state, action)"))
        #expect(stubSource.contains("state = newState"))
    }

    @Test("resolveAndEmit against a hidden-mutability body throws .hiddenMutability (M8.B)")
    func resolveAndEmitHiddenMutabilityRejected() throws {
        let directory = try makeFixtureDirectory(name: "PipelineHiddenMutability")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeFile(
            in: directory,
            relativePath: "Sources/MyApp",
            named: "Reducer.swift",
            contents: """
            enum Counter {
                static var hits = 0
                static func reduce(_ s: AppState, _ a: AppAction) -> AppState {
                    Counter.hits += 1
                    return s
                }
            }
            """
        )
        do {
            _ = try VerifyInteractionPipeline.resolveAndEmit(
                target: "MyApp",
                workingDirectory: directory
            )
            Issue.record("expected .hiddenMutability error")
        } catch let error as VerifyInteractionError {
            switch error {
            case let .hiddenMutability(reducer):
                #expect(reducer == "Counter.reduce")

            default:
                Issue.record("expected .hiddenMutability, got \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("VerifyInteractionPipelineTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writeFile(
        in directory: URL,
        relativePath: String,
        named name: String,
        contents: String
    ) throws {
        let dir = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: dir.appendingPathComponent(name))
    }
}
