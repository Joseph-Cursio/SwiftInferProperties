import ComposableArchitecture

// C2 widening (cycle 128) — real `@Reducer`, all-payload-free, broadening
// idempotence witness-vocabulary coverage: `select` (exact), `selectFirst`
// (select* prefix), `showDetail` (show* prefix). Phase A full exploration.
@Reducer
struct SelectionFeature {
    @ObservableState
    struct State: Equatable {
        var index = 0
        var detail = false
    }

    enum Action {
        case advance       // driver — index += 1
        case select        // idempotent witness — index = 0
        case selectFirst   // idempotent witness — index = 0
        case showDetail    // idempotent witness — detail = true
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .advance:
                state.index += 1
                return .none
            case .select:
                state.index = 0
                return .none
            case .selectFirst:
                state.index = 0
                return .none
            case .showDetail:
                state.detail = true
                return .none
            }
        }
    }
}
