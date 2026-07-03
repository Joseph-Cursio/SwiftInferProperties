// TCA determinism corpus, fixture 1 of 3 — a pure reducer.
// No dependency, no nondeterminism: two applications of the same
// (state, action) are equal → measured-bothPass → verified.
import ComposableArchitecture

@Reducer
struct PureCounterFeature {
    @ObservableState
    struct State: Equatable {
        var count = 0
    }
    enum Action {
        case increment
        case decrement
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .increment: state.count += 1
            case .decrement: state.count -= 1
            }
            return .none
        }
    }
}
