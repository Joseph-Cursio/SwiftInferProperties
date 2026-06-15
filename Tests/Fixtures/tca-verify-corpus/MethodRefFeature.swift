import ComposableArchitecture

// C2 widening (cycle 131) — real `@Reducer` using the method-REFERENCE body
// form `Reduce(handle)` ("Finding I", the kitlangton/Hex idiom) rather than
// the inline-closure form every other fixture uses. Exercises the second
// `.tca` discovery path (`emitCandidateForMethodRef`) end-to-end. All
// payload-free → Phase A; `dismiss` is the idempotent witness.
@Reducer
struct MethodRefFeature {
    @ObservableState
    struct State: Equatable {
        var open = false
        var loading = false
    }

    enum Action {
        case present   // driver — open = true
        case dismiss   // idempotent witness — open = false
        case load      // driver — loading = true
    }

    var body: some Reducer<State, Action> {
        Reduce(handle)
    }

    func handle(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .present:
            state.open = true
            return .none
        case .dismiss:
            state.open = false
            return .none
        case .load:
            state.loading = true
            return .none
        }
    }
}
