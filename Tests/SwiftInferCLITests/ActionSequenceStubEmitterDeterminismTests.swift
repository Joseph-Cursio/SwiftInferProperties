import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// V2.0 Phase 2 (Redux) — determinism-invariant emission tests for
// ActionSequenceStubEmitter. Determinism is the 6th interaction family and
// the only per-step *two-call* check: at each step it applies the loop's
// current `action` to the current `state` twice and asserts equality
// (`reduce(s, a) == reduce(s, a)`), unlike idempotence's post-loop
// single-witness double-apply.

@Suite("ActionSequenceStubEmitter — Phase 2 determinism per-step check")
struct StubEmitterDeterminismTests {

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

    private func determinismInvariant(
        candidateName: String = "reduce"
    ) -> InteractionInvariantSuggestion {
        let predicate = "reduce(s, a) == reduce(s, a)"
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .determinism,
            reducerQualifiedName: candidateName,
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: .determinism,
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

    @Test("Determinism embeds the two-call comparison PER-STEP, inside the action loop")
    func determinismEmbedsPerStepCheck() throws {
        let source = try ActionSequenceStubEmitter.emit(
            inputs(candidate(), invariant: determinismInvariant())
        )
        #expect(source.contains("let detFirst = reduce(state, action)"))
        #expect(source.contains("let detSecond = reduce(state, action)"))
        #expect(source.contains("precondition(detFirst == detSecond"))
        #expect(source.contains("Determinism invariant violated"))
        // Per-step: the comparison uses the loop variable `action`, and lands
        // after the apply line but before the inner loop closes — NOT a
        // post-loop single-witness check like idempotence.
        #expect(source.contains("let once =") == false)
        let applyIndex = source.range(of: "state = reduce(state, action)")!.upperBound
        let detIndex = source.range(of: "let detFirst = reduce(state, action)")!.lowerBound
        #expect(applyIndex <= detIndex)
    }

    @Test("Determinism header comment names the family")
    func determinismHeaderComment() throws {
        let source = try ActionSequenceStubEmitter.emit(
            inputs(candidate(), invariant: determinismInvariant())
        )
        #expect(source.contains("// Invariant family: determinism"))
    }

    @Test("makeDeterminismCheck (inout S, A) -> Void — two fresh applies from the same state")
    func makeDeterminismCheckInoutVoid() {
        let block = ActionSequenceStubEmitter.makeDeterminismCheck(
            shape: .inoutStateActionReturnsVoid,
            reducerCall: "reduce"
        )
        #expect(block.count == 5)
        #expect(block[0] == "var detFirst = state")
        #expect(block[1] == "reduce(&detFirst, action)")
        #expect(block[2] == "var detSecond = state")
        #expect(block[3] == "reduce(&detSecond, action)")
        #expect(block[4].contains("precondition(detFirst == detSecond"))
    }

    @Test("makeDeterminismCheck ReSwift reverses the args (action, state)")
    func makeDeterminismCheckReSwiftReversesArgs() {
        let block = ActionSequenceStubEmitter.makeDeterminismCheck(
            shape: .stateActionReturnsState,
            reducerCall: "appReducer",
            actionFirst: true
        )
        #expect(block.contains("let detFirst = appReducer(action, state)"))
        #expect(block.contains("let detSecond = appReducer(action, state)"))
    }

    @Test("makeDeterminismCheck TCA pins dependencies, then drives the reducer twice")
    func makeDeterminismCheckTCA() {
        let block = ActionSequenceStubEmitter.makeDeterminismCheck(
            shape: .inoutStateActionReturnsVoid,
            reducerCall: "reduce",
            isTCA: true
        )
        let joined = block.joined(separator: "\n")
        // Declared @Dependencies pinned to constants before the two applications.
        #expect(joined.contains("withDependencies {"))
        #expect(joined.contains("$0.date = .constant(Date(timeIntervalSince1970: 0))"))
        #expect(joined.contains("$0.uuid = .constant("))
        #expect(joined.contains("$0.continuousClock = ImmediateClock()"))
        #expect(joined.contains("} operation: {"))
        // Two applications of the same (state, action), compared.
        #expect(joined.contains("_ = reducer.reduce(into: &detFirst, action: action)"))
        #expect(joined.contains("_ = reducer.reduce(into: &detSecond, action: action)"))
        #expect(joined.contains("precondition(detFirst == detSecond"))
    }

    @Test("makeDeterminismCheck Mobius extracts Next.model from each application")
    func makeDeterminismCheckMobius() {
        let block = ActionSequenceStubEmitter.makeDeterminismCheck(
            shape: .stateActionReturnsStateAndEffect,
            reducerCall: "update",
            isMobius: true
        )
        #expect(block[0] == "let detFirst = update(state, action).model ?? state")
        #expect(block[1] == "let detSecond = update(state, action).model ?? state")
        #expect(block[2].contains("precondition(detFirst == detSecond"))
    }
}
