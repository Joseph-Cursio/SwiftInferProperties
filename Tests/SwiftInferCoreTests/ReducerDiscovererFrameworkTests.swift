import Foundation
@testable import SwiftInferCore
import Testing

// ReSwift + Mobius reducer-shape vocabulary. ReSwift's `(Action, State?)
// -> State` (Action-first, Optional incoming State) and Mobius's `(Model,
// Event) -> Next<Model, Effect>` (effect-bearing `Next<…>` return) are
// recognized at discovery, labeled via `carrierKind`, and mapped onto the
// existing signature shapes for §4 scoring. Measured-verify is gated
// separately (see ActionSequenceStubEmitter).
@Suite("ReducerDiscoverer — ReSwift / Mobius vocabulary")
struct ReducerDiscovererFrameworkTests {

    // MARK: - ReSwift: (Action, State?) -> State

    @Test("ReSwift free reducer (Action, State?) -> State — un-reverses State/Action, labels .reSwift")
    func reSwiftFreeReducer() {
        let source = """
        func counterReducer(action: CounterAction, state: CounterState?) -> CounterState {
            return state ?? CounterState()
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        let candidate = result[0]
        #expect(candidate.carrierKind == .reSwift)
        #expect(candidate.signatureShape == .stateActionReturnsState)
        // Un-reversed: State is the Optional param's wrapped type, Action the first param.
        #expect(candidate.stateTypeName == "CounterState")
        #expect(candidate.actionTypeName == "CounterAction")
    }

    @Test("ReSwift recognizes the Optional<State> spelling too")
    func reSwiftOptionalGenericSpelling() {
        let source = """
        func appReducer(action: AppAction, state: Optional<AppState>) -> AppState {
            return state ?? AppState()
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].carrierKind == .reSwift)
        #expect(result[0].stateTypeName == "AppState")
        #expect(result[0].actionTypeName == "AppAction")
    }

    @Test("ReSwift FP guard: a scalar State is rejected (reducers don't have scalar State)")
    func reSwiftRejectsScalarState() {
        // `(CounterAction, Int?) -> Int` matches ONLY the ReSwift shape
        // (the canonical path needs return == first param, and Int !=
        // CounterAction), so the empty result isolates the ReSwift scalar
        // guard rather than the canonical two-scalar filter.
        let source = """
        func pick(action: CounterAction, state: Int?) -> Int {
            return state ?? 0
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.isEmpty)
    }

    // MARK: - Mobius: (Model, Event) -> Next<Model, Effect>

    @Test("Mobius update (Model, Event) -> Next<Model, Effect> — labels .mobius, effect-bearing shape")
    func mobiusUpdate() {
        let source = """
        func update(_ model: CounterModel, _ event: CounterEvent) -> Next<CounterModel, CounterEffect> {
            return .next(model)
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        let candidate = result[0]
        #expect(candidate.carrierKind == .mobius)
        #expect(candidate.signatureShape == .stateActionReturnsStateAndEffect)
        #expect(candidate.stateTypeName == "CounterModel")
        #expect(candidate.actionTypeName == "CounterEvent")
    }

    @Test("Mobius update as an instance method sets enclosingTypeName")
    func mobiusInstanceMethod() {
        let source = """
        struct CounterLogic {
            func update(_ model: CounterModel, _ event: CounterEvent) -> Next<CounterModel, CounterEffect> {
                return .next(model)
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].carrierKind == .mobius)
        #expect(result[0].enclosingTypeName == "CounterLogic")
    }

    @Test("Next<X, E> whose first generic isn't the State param is not Mobius (no shape match)")
    func mobiusRejectsMismatchedNextModel() {
        let source = """
        func update(_ model: CounterModel, _ event: CounterEvent) -> Next<OtherModel, CounterEffect> {
            fatalError()
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.isEmpty)
    }

    // MARK: - Workflow (Square): apply(toState: inout State) -> Output?

    @Test("Workflow apply(toState: inout State) -> Output? — Action is the enclosing type, labels .workflow")
    func workflowApplyMethod() {
        let source = """
        struct IncrementAction {
            func apply(toState state: inout CounterState) -> CounterOutput? {
                state.count += 1
                return nil
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        let candidate = result[0]
        #expect(candidate.carrierKind == .workflow)
        // Action is the enclosing type (Self); State is the inout param.
        #expect(candidate.actionTypeName == "IncrementAction")
        #expect(candidate.stateTypeName == "CounterState")
        #expect(candidate.signatureShape == .inoutStateActionReturnsEffect)
    }

    @Test("Workflow apply with no Output return maps to the void shape")
    func workflowApplyVoidReturn() {
        let source = """
        struct ResetAction {
            func apply(toState state: inout CounterState) {
                state = CounterState()
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].carrierKind == .workflow)
        #expect(result[0].signatureShape == .inoutStateActionReturnsVoid)
    }

    @Test("Workflow v4/v5 apply(toState:context:) arity-2 form is discovered (current workflow-swift)")
    func workflowApplyWithContext() {
        // workflow-swift v4.0.0+ added the `context: ApplyContext<…>` arg.
        // It's framework plumbing, not the Action — discovered + scored the
        // same as v3's arity-1 (verify stays gated: ApplyContext is not
        // publicly constructible).
        let source = """
        enum IncrementAction {
            case bump
            func apply(toState state: inout CounterState, context: ApplyContext<CounterWorkflow>) -> CounterOutput? {
                state.count += 1
                return nil
            }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].carrierKind == .workflow)
        #expect(result[0].actionTypeName == "IncrementAction")
        #expect(result[0].stateTypeName == "CounterState")
    }

    @Test("an arity-2 apply whose 2nd arg isn't `context:` is not Workflow")
    func workflowRejectsNonContextSecondArg() {
        let source = """
        struct NotAnAction {
            func apply(toState state: inout CounterState, extra: Int) -> CounterOutput? { nil }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.isEmpty)
    }

    @Test("a free apply(toState:) function (no enclosing Action type) is not Workflow")
    func workflowRejectsFreeFunction() {
        // No enclosing type → no Action → not a WorkflowAction; and arity-1
        // is rejected by the canonical guard too.
        let source = """
        func apply(toState state: inout CounterState) -> CounterOutput? { nil }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.isEmpty)
    }

    @Test("apply with a non-`toState` label is not Workflow")
    func workflowRejectsWrongLabel() {
        let source = """
        struct NotAnAction {
            func apply(to state: inout CounterState) -> CounterOutput? { nil }
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.isEmpty)
    }

    // MARK: - Regression: canonical shapes keep their labels

    @Test("a canonical free (S, A) -> S stays .elmStyle, not .reSwift/.mobius")
    func canonicalElmUnaffected() {
        let source = """
        func reduce(_ state: AppState, _ action: AppAction) -> AppState { state }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].carrierKind == .elmStyle)
    }

    @Test("a canonical (S, A) -> (S, Effect<A>) tuple stays .generic, not .mobius")
    func canonicalTupleEffectUnaffected() {
        let source = """
        func reduce(_ state: AppState, _ action: AppAction) -> (AppState, Effect<AppAction>) {
            return (state, .none)
        }
        """
        let result = ReducerDiscoverer.discover(source: source, file: "F.swift")
        #expect(result.count == 1)
        #expect(result[0].carrierKind == .generic)
        #expect(result[0].signatureShape == .stateActionReturnsStateAndEffect)
    }
}
