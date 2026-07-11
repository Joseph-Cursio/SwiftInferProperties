import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
import Testing

/// The reducer-path async slice (collections/async workplan Phase 4,
/// standing-instruction trigger fired on a real corpus): a
/// clock-deterministic-annotated async reducer is admitted through the
/// pipeline, the verifier wrapper flips to `static func main() async`,
/// every reducer call is awaited (apply step + family checks — the
/// determinism apply-twice-compare first), and all-sync output stays
/// byte-identical. Mirrors `ViewModelAsyncActionTests`.
@Suite
struct ReducerAsyncSliceTests {

    private func candidate(
        signatureShape: ReducerSignatureShape = .stateActionReturnsState,
        isAsync: Bool = false,
        isClockDeterministic: Bool = false
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/MyApp/Reducer.swift:2",
            enclosingTypeName: "Counter",
            functionName: "reduce",
            signatureShape: signatureShape,
            stateTypeName: "AppState",
            actionTypeName: "AppAction",
            isAsync: isAsync,
            isClockDeterministic: isClockDeterministic
        )
    }

    private func determinismInvariant() -> InteractionInvariantSuggestion {
        let predicate = "reduce(s, a) == reduce(s, a)"
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .determinism,
            reducerQualifiedName: "Counter.reduce",
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: .determinism,
            reducerQualifiedName: "Counter.reduce",
            reducerLocation: "Sources/MyApp/Reducer.swift:2",
            stateTypeName: "AppState",
            actionTypeName: "AppAction",
            predicate: predicate,
            score: 30,
            tier: .possible,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: ISO8601DateFormatter().date(from: "2026-07-11T10:00:00Z")!
        )
    }

    @Test("Annotated async reducer passes resolveAndEmit with an async verifier")
    func annotatedAsyncReducerIsAdmitted() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReducerAsyncSlice-\(UUID().uuidString)")
        let sources = directory.appendingPathComponent("Sources/MyApp")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try """
        enum Counter {
            /// @lint.determinism clock_deterministic
            static func reduce(_ s: AppState, _ a: AppAction) async -> AppState {
                s
            }
        }
        """.write(
            to: sources.appendingPathComponent("Reducer.swift"),
            atomically: true,
            encoding: .utf8
        )
        let (matched, stubSource) = try VerifyInteractionPipeline.resolveAndEmit(
            target: "MyApp",
            workingDirectory: directory
        )
        #expect(matched.isAsync)
        #expect(matched.isClockDeterministic)
        #expect(stubSource.contains("static func main() async {"))
        #expect(stubSource.contains("state = await Counter.reduce(state, action)"))
    }

    @Test("Async apply step awaits the reducer for every signature shape")
    func applyStepAwaitsEveryShape() {
        let byShape: [ReducerSignatureShape: String] = [
            .stateActionReturnsState: "state = await Counter.reduce(state, action)",
            .inoutStateActionReturnsVoid: "await Counter.reduce(&state, action)",
            .stateActionReturnsStateAndEffect: "let (newState, _) = await Counter.reduce(state, action)",
            .inoutStateActionReturnsEffect: "_ = await Counter.reduce(&state, action)"
        ]
        for (shape, expected) in byShape {
            let step = ActionSequenceStubEmitter.makeApplyStep(
                shape: shape,
                reducerCall: "Counter.reduce",
                isAsync: true
            )
            #expect(step.contains(expected), "shape \(shape.rawValue)")
        }
    }

    @Test("Determinism per-step check awaits both applications")
    func determinismCheckAwaitsBothCalls() throws {
        let source = try ActionSequenceStubEmitter.emit(.init(
            candidate: candidate(isAsync: true, isClockDeterministic: true),
            userModuleName: "MyApp",
            sequenceCount: 16,
            invariant: determinismInvariant()
        ))
        #expect(source.contains("let detFirst = await Counter.reduce(state, action)"))
        #expect(source.contains("let detSecond = await Counter.reduce(state, action)"))
        #expect(source.contains("static func main() async {"))
    }

    @Test("Idempotence post-loop check awaits the double-apply")
    func idempotenceCheckAwaitsDoubleApply() {
        let check = ActionSequenceStubEmitter.makeIdempotenceCheck(
            actionExpr: "AppAction.increment",
            shape: .stateActionReturnsState,
            reducerCall: "Counter.reduce",
            isAsync: true
        )
        #expect(check.contains("let once = await Counter.reduce(state, AppAction.increment)"))
        #expect(check.contains("let twice = await Counter.reduce(once, AppAction.increment)"))
    }

    @Test("Sync candidate output carries no async marker or await")
    func syncOutputIsUntouched() throws {
        let source = try ActionSequenceStubEmitter.emit(.init(
            candidate: candidate(),
            userModuleName: "MyApp",
            sequenceCount: 16,
            invariant: determinismInvariant()
        ))
        #expect(source.contains("static func main() {"))
        #expect(source.contains(" async") == false)
        #expect(source.contains("await ") == false)
    }

    @Test("Trace replay goes async and awaits the apply step for an async candidate")
    func traceReplayGoesAsync() {
        let asyncTrace = InteractionTraceEmitter.emit(.init(
            candidate: candidate(isAsync: true, isClockDeterministic: true),
            userModuleName: "MyApp",
            sequenceCount: 16
        ))
        #expect(asyncTrace.contains("func replay() async {"))
        #expect(asyncTrace.contains("state = await Counter.reduce(state, action)"))

        let syncTrace = InteractionTraceEmitter.emit(.init(
            candidate: candidate(),
            userModuleName: "MyApp",
            sequenceCount: 16
        ))
        #expect(syncTrace.contains("func replay() {"))
        #expect(syncTrace.contains("await ") == false)
    }
}
