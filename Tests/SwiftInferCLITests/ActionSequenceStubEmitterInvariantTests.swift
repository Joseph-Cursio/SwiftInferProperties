import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// V2.0 M4.D — invariant-aware emission tests for
// ActionSequenceStubEmitter. The base "ran cleanly" mode is covered
// by ActionSequenceStubEmitterTests; this suite exercises the
// family-specific predicate embedding (Conservation per-step check
// + Idempotence post-loop double-apply).

@Suite("ActionSequenceStubEmitter — V2.0 M4.D family-aware predicate embedding")
struct ActionSequenceStubEmitterInvariantTests {

    private func candidate(
        signatureShape: ReducerSignatureShape = .stateActionReturnsState,
        enclosingTypeName: String? = nil,
        functionName: String = "reduce"
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/MyApp/F.swift:1",
            enclosingTypeName: enclosingTypeName,
            functionName: functionName,
            signatureShape: signatureShape,
            stateTypeName: "AppState",
            actionTypeName: "AppAction",
            carrierKind: enclosingTypeName == nil ? .elmStyle : .generic
        )
    }

    private func conservationInvariant(
        predicate: String = "state.count == state.items.count",
        candidateName: String = "reduce"
    ) -> InteractionInvariantSuggestion {
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .conservation,
            reducerQualifiedName: candidateName,
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: .conservation,
            reducerQualifiedName: candidateName,
            reducerLocation: "Sources/MyApp/F.swift:1",
            stateTypeName: "AppState",
            actionTypeName: "AppAction",
            predicate: predicate,
            score: 30,
            tier: .possible,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: ISO8601DateFormatter().date(from: "2026-05-15T10:00:00Z")!
        )
    }

    private func idempotenceInvariant(
        actionCaseShorthand: String = ".refresh",
        candidateName: String = "reduce"
    ) -> InteractionInvariantSuggestion {
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .idempotence,
            reducerQualifiedName: candidateName,
            predicate: actionCaseShorthand
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: .idempotence,
            reducerQualifiedName: candidateName,
            reducerLocation: "Sources/MyApp/F.swift:1",
            stateTypeName: "AppState",
            actionTypeName: "AppAction",
            predicate: actionCaseShorthand,
            score: 30,
            tier: .possible,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: ISO8601DateFormatter().date(from: "2026-05-15T10:00:00Z")!
        )
    }

    private func inputs(
        _ candidate: ReducerCandidate,
        invariant: InteractionInvariantSuggestion? = nil
    ) -> ActionSequenceStubEmitter.Inputs {
        ActionSequenceStubEmitter.Inputs(
            candidate: candidate,
            userModuleName: "MyApp",
            sequenceCount: 16,
            invariant: invariant
        )
    }

    // MARK: - Backward compat: nil invariant = M3.B behavior

    @Test("nil invariant emits the M3.B `ran cleanly` shape — no precondition, no double-apply")
    func nilInvariantPreservesM3BBehavior() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate()))
        #expect(!source.contains("precondition("))
        #expect(!source.contains("let once ="))
    }

    // MARK: - Conservation per-step check

    @Test("Conservation invariant embeds precondition(<predicate>) inside the per-action loop")
    func conservationEmbedsPerStepCheck() throws {
        let source = try ActionSequenceStubEmitter.emit(
            inputs(candidate(), invariant: conservationInvariant())
        )
        #expect(source.contains("precondition(state.count == state.items.count"))
        #expect(source.contains("Conservation invariant violated"))
        // The precondition lives inside the inner action loop — should
        // appear AFTER the `state = reduce(state, action)` line and
        // BEFORE the loop's closing brace.
        let applyIndex = source.range(of: "state = reduce(state, action)")!.upperBound
        let precondIndex = source.range(of: "precondition(state.count")!.lowerBound
        #expect(applyIndex <= precondIndex)
    }

    @Test("Conservation header comment names the family + predicate")
    func conservationHeaderComment() throws {
        let source = try ActionSequenceStubEmitter.emit(
            inputs(candidate(), invariant: conservationInvariant())
        )
        #expect(source.contains("// Invariant family: conservation"))
        #expect(source.contains("// Predicate: state.count == state.items.count"))
    }

    // MARK: - Idempotence post-loop check

    @Test("Idempotence (S, A) -> S — emits post-loop reduce-twice + equality precondition")
    func idempotencePostLoopStateReturnsState() throws {
        let source = try ActionSequenceStubEmitter.emit(
            inputs(candidate(), invariant: idempotenceInvariant(actionCaseShorthand: ".refresh"))
        )
        #expect(source.contains("let once = reduce(state, .refresh)"))
        #expect(source.contains("let twice = reduce(once, .refresh)"))
        #expect(source.contains("precondition(once == twice"))
        #expect(source.contains("Idempotence invariant violated for .refresh"))
    }

    @Test("Idempotence (inout S, A) -> Void — uses copy-and-mutate dance")
    func idempotencePostLoopInoutVoid() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(
            candidate(signatureShape: .inoutStateActionReturnsVoid),
            invariant: idempotenceInvariant(actionCaseShorthand: ".reset")
        ))
        #expect(source.contains("var once = state"))
        #expect(source.contains("reduce(&once, .reset)"))
        #expect(source.contains("var twice = once"))
        #expect(source.contains("reduce(&twice, .reset)"))
        #expect(source.contains("precondition(once == twice"))
    }

    @Test("Idempotence post-loop check lives outside the inner action loop")
    func idempotenceLivesOutsideInnerLoop() throws {
        let source = try ActionSequenceStubEmitter.emit(
            inputs(candidate(), invariant: idempotenceInvariant())
        )
        // The post-loop check appears AFTER the inner loop's closing
        // brace (the one closing `for action in actions { ... }`) but
        // BEFORE `clean += 1`.
        guard let cleanIndex = source.range(of: "clean += 1")?.lowerBound else {
            Issue.record("expected `clean += 1` in stub")
            return
        }
        guard let onceIndex = source.range(of: "let once = reduce")?.lowerBound else {
            Issue.record("expected `let once = reduce` in stub")
            return
        }
        #expect(onceIndex < cleanIndex)
    }

    // MARK: - Biconditional / iff (M7 ships — all five families supported)

    @Test("Biconditional invariant — M7 ships, embeds precondition like Conservation")
    func biconditionalEmbedsPrecondition() throws {
        let predicate = "state.isLoading == (state.activeTask != nil)"
        let biconditional = InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: "bicond::reduce::isLoading"),
            family: .biconditional,
            reducerQualifiedName: "reduce",
            reducerLocation: "F.swift:1",
            stateTypeName: "AppState",
            actionTypeName: "AppAction",
            predicate: predicate,
            score: 30,
            tier: .possible,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: Date()
        )
        let source = try ActionSequenceStubEmitter.emit(
            inputs(candidate(), invariant: biconditional)
        )
        #expect(source.contains("precondition(\(predicate)"))
        #expect(source.contains("Biconditional invariant violated"))
    }

    @Test("Referential-integrity invariant — M6 ships, embeds precondition like Conservation")
    func referentialIntegrityEmbedsPrecondition() throws {
        let predicate = "state.selectedID == nil || state.items.contains { $0.id == state.selectedID }"
        let referentialIntegrity = InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: "refint::reduce::sel"),
            family: .referentialIntegrity,
            reducerQualifiedName: "reduce",
            reducerLocation: "F.swift:1",
            stateTypeName: "AppState",
            actionTypeName: "AppAction",
            predicate: predicate,
            score: 30,
            tier: .possible,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: Date()
        )
        let source = try ActionSequenceStubEmitter.emit(
            inputs(candidate(), invariant: referentialIntegrity)
        )
        #expect(source.contains("precondition(\(predicate)"))
        #expect(source.contains("Referential-integrity invariant violated"))
    }

    @Test("Cardinality invariant — M5 ships, embeds precondition like Conservation")
    func cardinalityEmbedsPrecondition() throws {
        let predicate = "(state.activeSheet != nil ? 1 : 0) + (state.isFullScreen ? 1 : 0) <= 1"
        let cardinality = InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: "cardinality::reduce::sheet"),
            family: .cardinality,
            reducerQualifiedName: "reduce",
            reducerLocation: "F.swift:1",
            stateTypeName: "AppState",
            actionTypeName: "AppAction",
            predicate: predicate,
            score: 30,
            tier: .possible,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: Date()
        )
        let source = try ActionSequenceStubEmitter.emit(
            inputs(candidate(), invariant: cardinality)
        )
        #expect(source.contains("precondition(\(predicate)"))
        #expect(source.contains("Cardinality invariant violated"))
    }

    // MARK: - Helper-function shape

    @Test("makeIdempotenceCheck (S, A) -> S — produces 3-line block")
    func makeIdempotenceCheckStateActionReturnsState() {
        let block = ActionSequenceStubEmitter.makeIdempotenceCheck(
            actionExpr: ".foo",
            shape: .stateActionReturnsState,
            reducerCall: "reduce"
        )
        #expect(block.count == 3)
        #expect(block[0] == "let once = reduce(state, .foo)")
        #expect(block[1] == "let twice = reduce(once, .foo)")
        #expect(block[2].contains("precondition(once == twice"))
    }

    @Test("makeIdempotenceCheck (inout S, A) -> Void — produces 5-line block")
    func makeIdempotenceCheckInoutVoid() {
        let block = ActionSequenceStubEmitter.makeIdempotenceCheck(
            actionExpr: ".bar",
            shape: .inoutStateActionReturnsVoid,
            reducerCall: "reduce"
        )
        #expect(block.count == 5)
        #expect(block[0] == "var once = state")
        #expect(block[3] == "reduce(&twice, .bar)")
    }

    @Test("makePerStepCheck on Conservation returns a precondition; nil/other families return empty")
    func makePerStepCheckShape() {
        let nilCheck = ActionSequenceStubEmitter.makePerStepCheck(invariant: nil)
        #expect(nilCheck.isEmpty)
        let conservation = ActionSequenceStubEmitter.makePerStepCheck(
            invariant: conservationInvariant()
        )
        #expect(conservation.count == 1)
        #expect(conservation[0].contains("precondition(state.count"))
        let idempotence = ActionSequenceStubEmitter.makePerStepCheck(
            invariant: idempotenceInvariant()
        )
        #expect(idempotence.isEmpty)
    }
}

// V2.0 M8.A — effect-discarding idempotence-check shape assertions
// for the two effect-bearing signatures. Extension-grouped so the
// parent struct's body stays under SwiftLint's type_body_length cap.
extension ActionSequenceStubEmitterInvariantTests {

    @Test("makeIdempotenceCheck (S, A) -> (S, Effect<A>) — captures + discards effect (M8.A)")
    func makeIdempotenceCheckStateActionReturnsStateAndEffect() {
        let block = ActionSequenceStubEmitter.makeIdempotenceCheck(
            actionExpr: ".tap",
            shape: .stateActionReturnsStateAndEffect,
            reducerCall: "reduce"
        )
        #expect(block.count == 3)
        #expect(block[0] == "let (once, _) = reduce(state, .tap)")
        #expect(block[1] == "let (twice, _) = reduce(once, .tap)")
        #expect(block[2].contains("precondition(once == twice"))
    }

    @Test("makeIdempotenceCheck (inout S, A) -> Effect<A> — captures + discards effect (M8.A)")
    func makeIdempotenceCheckInoutEffect() {
        let block = ActionSequenceStubEmitter.makeIdempotenceCheck(
            actionExpr: ".refresh",
            shape: .inoutStateActionReturnsEffect,
            reducerCall: "reduce"
        )
        #expect(block.count == 5)
        #expect(block[0] == "var once = state")
        #expect(block[1] == "_ = reduce(&once, .refresh)")
        #expect(block[2] == "var twice = once")
        #expect(block[3] == "_ = reduce(&twice, .refresh)")
        #expect(block[4].contains("precondition(once == twice"))
    }
}
