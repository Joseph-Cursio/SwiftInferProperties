import ComposableArchitecture

/// TestStore Trace Mining — measured proof corpus. A real `@Reducer` covering
/// two things at once:
///   - **Slice-3b payload generalization** via `adjust(Int)`, a NON-witness
///     payload-bearing case: a sibling `TestStore` test sends `.adjust(5)`,
///     which the miner generalizes to the canned `.adjust(0)`.
///   - **The payload-bearing idempotence-witness fix** via `select(Int)`, a
///     WITNESS (`select*`) that carries a payload. The reducer emitter used to
///     emit the bare `.select` here (uncompilable → build-fail → coverage-
///     pending); the fix synthesizes the payload (`.select(0)`, x-curried), so
///     it now verifies. `select(v)` is genuinely idempotent (sets, not
///     accumulates), so it verifies bothPass.
///   - `reset` is the payload-free idempotence witness (the baseline).
@Reducer
struct TraceFeature {

    @ObservableState
    struct State: Equatable {
        var selected: Int = 0
    }

    enum Action {
        case reset
        case select(Int)
        case adjust(Int)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .reset:
                state.selected = 0

            case let .select(value):
                state.selected = value

            case let .adjust(value):
                state.selected = value
            }
            return .none
        }
    }
}
