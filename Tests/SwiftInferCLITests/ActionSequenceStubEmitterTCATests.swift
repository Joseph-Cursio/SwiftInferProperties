import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// Cycle 122 (Phase A) — `.tca` carrier emitter tests. Split from
// ActionSequenceStubEmitterTests (own file, per the ReducerDiscovererTCATests
// pattern) to keep both structs under SwiftLint's type_body_length cap.
// Asserts on the emitted stub *source* — no subprocess; the end-to-end
// build/run proof is TCACarrierMeasuredTests.

@Suite("ActionSequenceStubEmitter — Cycle 122 .tca carrier path")
struct ActionSequenceStubEmitterTCATests {

    private func tcaCandidate(actionCaseNames: [String]) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/App/Counter.swift:3",
            enclosingTypeName: "Counter",
            functionName: "body",
            signatureShape: .inoutStateActionReturnsEffect,
            stateTypeName: "Counter.State",
            actionTypeName: "Counter.Action",
            carrierKind: .tca,
            actionCaseNames: actionCaseNames
        )
    }

    private func inputs(
        _ candidate: ReducerCandidate,
        invariant: InteractionInvariantSuggestion? = nil
    ) -> ActionSequenceStubEmitter.Inputs {
        ActionSequenceStubEmitter.Inputs(
            candidate: candidate,
            userModuleName: "App",
            invariant: invariant
        )
    }

    @Test("`.tca` with a payload-bearing Action (no case list) throws tcaActionNotEnumerable")
    func tcaWithoutCaseListIsRejected() {
        // Empty actionCaseNames is the discovery signal for "Action has a
        // payload case (or none found)" — Phase A can't enumerate it.
        #expect(
            throws: ActionSequenceStubEmitter.EmitError
                .tcaActionNotEnumerable(actionType: "Counter.Action")
        ) {
            _ = try ActionSequenceStubEmitter.emit(inputs(tcaCandidate(actionCaseNames: [])))
        }
    }

    @Test("`.tca` with a payload-free case list emits the instance-relative TCA shape")
    func tcaWithCaseListEmitsInstanceInvocation() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(
            tcaCandidate(actionCaseNames: ["increment", "decrement", "closeMenu"])
        ))
        // 1. CA import (not `import <userModule>` — corpus is co-compiled).
        #expect(source.contains("import ComposableArchitecture"))
        // 2. explicit-case generator from the captured list (not forCaseIterable).
        #expect(source.contains(
            "Gen.element(of: [Counter.Action.increment, Counter.Action.decrement, "
                + "Counter.Action.closeMenu])"
        ))
        #expect(!source.contains("forCaseIterable"))
        // 3. instance setup + instance-relative invocation.
        #expect(source.contains("let reducer = Counter()"))
        #expect(source.contains("_ = reducer.reduce(into: &state, action: action)"))
    }

    @Test("`.tca` idempotence check double-applies the witness through the instance")
    func tcaIdempotenceUsesInstance() throws {
        let invariant = InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: "idempotence|Counter.body|.closeMenu"),
            family: .idempotence,
            reducerQualifiedName: "Counter.body",
            reducerLocation: "Sources/App/Counter.swift:1",
            stateTypeName: "Counter.State",
            actionTypeName: "Counter.Action",
            predicate: ".closeMenu",
            score: 40,
            tier: .likely,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let source = try ActionSequenceStubEmitter.emit(inputs(
            tcaCandidate(actionCaseNames: ["increment", "closeMenu"]),
            invariant: invariant
        ))
        #expect(source.contains("_ = reducer.reduce(into: &once, action: .closeMenu)"))
        #expect(source.contains("_ = reducer.reduce(into: &twice, action: .closeMenu)"))
        #expect(source.contains("precondition(once == twice"))
    }
}
