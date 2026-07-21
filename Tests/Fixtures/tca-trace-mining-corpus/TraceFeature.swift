import ComposableArchitecture

/// TestStore Trace Mining — measured proof corpus. A real `@Reducer` with a
/// **payload-bearing** Action case (`adjust(Int)`) so the Slice-3b payload
/// generalization is exercised end-to-end: a sibling `TestStore` test sends
/// `.adjust(5)`, which the miner can't reconstruct verbatim (the `5` is a
/// literal here, but the mechanism replaces it with the canned `adjust(0)`),
/// plus the payload-free `reset` idempotence witness the invariant verifies.
/// `adjust` is deliberately a NON-witness name so `reset` is the sole surfaced
/// idempotence identity — the payload-bearing case exists only to be mined.
@Reducer
struct TraceFeature {

    @ObservableState
    struct State: Equatable {
        var selected: Int = 0
    }

    enum Action {
        case reset
        case adjust(Int)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .reset:
                state.selected = 0

            case let .adjust(value):
                state.selected = value
            }
            return .none
        }
    }
}
