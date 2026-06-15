import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// Cycle 122 (Phase A) — `.tca` carrier emitter tests. Split from
// ActionSequenceStubEmitterTests (own file, per the ReducerDiscovererTCATests
// pattern) to keep both structs under SwiftLint's type_body_length cap.
// Asserts on the emitted stub *source* — no subprocess; the end-to-end
// build/run proof is TCACarrierMeasuredTests.

@Suite("ActionSequenceStubEmitter — Cycle 122/125 .tca carrier path")
struct ActionSequenceStubEmitterTCATests {

    private func tcaCandidate(actionCases: [ActionCaseInfo]) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/App/Counter.swift:3",
            enclosingTypeName: "Counter",
            functionName: "body",
            signatureShape: .inoutStateActionReturnsEffect,
            stateTypeName: "Counter.State",
            actionTypeName: "Counter.Action",
            carrierKind: .tca,
            actionCases: actionCases
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

    @Test("`.tca` with no constructible case throws tcaActionNotEnumerable")
    func tcaWithNoConstructibleCaseIsRejected() {
        // Every case is a non-derivable composition payload → nothing for
        // the relaxed generator to explore.
        let cases = [
            ActionCaseInfo(name: "binding", payloadTypes: ["BindingAction<State>"]),
            ActionCaseInfo(name: "child", payloadTypes: ["Child.Action"])
        ]
        #expect(
            throws: ActionSequenceStubEmitter.EmitError
                .tcaActionNotEnumerable(actionType: "Counter.Action")
        ) {
            _ = try ActionSequenceStubEmitter.emit(inputs(tcaCandidate(actionCases: cases)))
        }
    }

    @Test("`.tca` all-payload-free emits a Gen.oneOf of always-cases + instance invocation")
    func tcaAllFreeEmitsOneOf() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(tcaCandidate(actionCases: [
            ActionCaseInfo(name: "increment"),
            ActionCaseInfo(name: "decrement"),
            ActionCaseInfo(name: "closeMenu")
        ])))
        #expect(source.contains("import ComposableArchitecture"))
        #expect(source.contains("Gen.oneOf("))
        #expect(source.contains("Gen.always(Counter.Action.increment)"))
        #expect(source.contains("Gen.always(Counter.Action.closeMenu)"))
        #expect(!source.contains("forCaseIterable"))
        #expect(source.contains("let reducer = Counter()"))
        #expect(source.contains("_ = reducer.reduce(into: &state, action: action)"))
    }

    @Test("Cycle 125 — mixed Action: raw case mapped, non-derivable case skipped")
    func tcaMixedActionGeneratesRawSkipsComposition() throws {
        let candidate = tcaCandidate(actionCases: [
            ActionCaseInfo(name: "closeMenu"),                        // free
            ActionCaseInfo(name: "setCount", payloadTypes: ["Int"]), // raw
            ActionCaseInfo(name: "child", payloadTypes: ["Child.Action"]) // excluded
        ])
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate))
        // free + raw generated...
        #expect(source.contains("Gen.always(Counter.Action.closeMenu)"))
        #expect(source.contains("Gen<Int>.int().map(Counter.Action.setCount)"))
        // ...non-derivable child case never appears in the generator.
        #expect(!source.contains("Counter.Action.child"))
        // Classification helpers agree on the excluded set.
        #expect(ActionSequenceStubEmitter.excludedCaseNames(candidate) == ["child"])
        #expect(ActionSequenceStubEmitter.constructibleCases(candidate).map(\.name)
            == ["closeMenu", "setCount"])
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
            tcaCandidate(actionCases: [
                ActionCaseInfo(name: "increment"),
                ActionCaseInfo(name: "closeMenu")
            ]),
            invariant: invariant
        ))
        #expect(source.contains("_ = reducer.reduce(into: &once, action: .closeMenu)"))
        #expect(source.contains("_ = reducer.reduce(into: &twice, action: .closeMenu)"))
        #expect(source.contains("precondition(once == twice"))
    }
}
