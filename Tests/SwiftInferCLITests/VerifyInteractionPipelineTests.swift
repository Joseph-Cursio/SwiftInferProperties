import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// V2.0 M3.C — pipeline orchestration tests. The candidate-resolution
// path (pin parsing + filtering) is unit-tested in isolation; the
// full `runPipeline(target:pinRaw:workingDirectory:)` is exercised
// via a fixture directory walk. The build-and-run integration test
// lands at M3.E once the v2.2.0 kit tag is published.

@Suite("VerifyInteractionPipeline — V2.0 M3.C orchestration")
struct VerifyInteractionPipelineTests {

    private func candidate(
        functionName: String,
        enclosingTypeName: String? = nil,
        signatureShape: ReducerSignatureShape = .stateActionReturnsState,
        carrierKind: ReducerCarrierKind = .elmStyle
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/Test/F.swift:1",
            enclosingTypeName: enclosingTypeName,
            functionName: functionName,
            signatureShape: signatureShape,
            stateTypeName: "S",
            actionTypeName: "A",
            carrierKind: carrierKind
        )
    }

    // MARK: - resolveCandidate — single match

    @Test("single candidate without a pin resolves directly")
    func singleCandidateNoPinResolvesDirectly() throws {
        let resolved = try VerifyInteractionPipeline.resolveCandidate(
            candidates: [candidate(functionName: "reduce")],
            pinRaw: nil
        )
        #expect(resolved.functionName == "reduce")
    }

    @Test("zero candidates without a pin throws noReducersDetected")
    func zeroCandidatesNoPinThrows() {
        #expect(throws: VerifyInteractionError.noReducersDetected) {
            _ = try VerifyInteractionPipeline.resolveCandidate(candidates: [], pinRaw: nil)
        }
    }

    @Test("multiple candidates without a pin throws requiresPin with all qualifiedNames")
    func multipleCandidatesNoPinThrows() {
        let candidates = [
            candidate(functionName: "reduceA"),
            candidate(functionName: "reduceB")
        ]
        #expect(throws: (any Error).self) {
            _ = try VerifyInteractionPipeline.resolveCandidate(candidates: candidates, pinRaw: nil)
        }
        // Specifically the requiresPin case:
        do {
            _ = try VerifyInteractionPipeline.resolveCandidate(candidates: candidates, pinRaw: nil)
            Issue.record("expected requiresPin error")
        } catch let error as VerifyInteractionError {
            switch error {
            case let .requiresPin(names):
                #expect(names == ["reduceA", "reduceB"])
            default:
                Issue.record("expected .requiresPin, got \(error)")
            }
        } catch {
            Issue.record("expected VerifyInteractionError, got \(error)")
        }
    }

    // MARK: - resolveCandidate — pinned

    @Test("pin filters candidate list to a single match")
    func pinFiltersToSingleMatch() throws {
        let candidates = [
            candidate(functionName: "reduceA"),
            candidate(functionName: "reduceB", enclosingTypeName: "Inbox", carrierKind: .generic)
        ]
        let resolved = try VerifyInteractionPipeline.resolveCandidate(
            candidates: candidates,
            pinRaw: "Inbox.reduceB"
        )
        #expect(resolved.functionName == "reduceB")
        #expect(resolved.enclosingTypeName == "Inbox")
    }

    @Test("pin matching zero candidates throws noMatchingReducer")
    func pinNoMatchThrows() {
        let candidates = [candidate(functionName: "reduce")]
        #expect(throws: VerifyInteractionError.noMatchingReducer(pin: "Missing.body")) {
            _ = try VerifyInteractionPipeline.resolveCandidate(candidates: candidates, pinRaw: "Missing.body")
        }
    }

    @Test("pin matching multiple candidates throws ambiguousPin")
    func pinAmbiguousThrows() {
        let candidates = [
            candidate(functionName: "reduce", enclosingTypeName: "InboxA", carrierKind: .generic),
            candidate(functionName: "reduce", enclosingTypeName: "InboxB", carrierKind: .generic)
        ]
        do {
            _ = try VerifyInteractionPipeline.resolveCandidate(
                candidates: candidates,
                pinRaw: "reduce"
            )
            Issue.record("expected ambiguousPin error")
        } catch let error as VerifyInteractionError {
            switch error {
            case let .ambiguousPin(pin, matches):
                #expect(pin == "reduce")
                #expect(matches.count == 2)
            default:
                Issue.record("expected .ambiguousPin, got \(error)")
            }
        } catch {
            Issue.record("expected VerifyInteractionError, got \(error)")
        }
    }

    @Test("module-prefixed pin surfaces ReducerPinError.moduleResolutionUnsupported")
    func modulePrefixedPinSurfacesError() {
        let candidates = [candidate(functionName: "reduce")]
        #expect(throws: ReducerPinError.moduleResolutionUnsupported(raw: "M.Inbox.reduce")) {
            _ = try VerifyInteractionPipeline.resolveCandidate(
                candidates: candidates,
                pinRaw: "M.Inbox.reduce"
            )
        }
    }

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
        try writeFile(
            in: directory,
            relativePath: "Sources/MyApp",
            named: "Effect.swift",
            contents: """
            func reduce(_ s: AppState, _ a: AppAction) -> (AppState, Effect<AppAction>) {
                return (s, .none)
            }
            """
        )
        let (candidate, stubSource) = try VerifyInteractionPipeline.resolveAndEmit(
            target: "MyApp",
            workingDirectory: directory
        )
        #expect(candidate.signatureShape == .stateActionReturnsStateAndEffect)
        // The effect half is captured into `_` and discarded — PRD §16 #1.
        #expect(stubSource.contains("let (newState, _) = reduce(state, action)"))
        #expect(stubSource.contains("state = newState"))
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
