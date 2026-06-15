import ComposableArchitecture

// C2 widening (cycle 133) — a COMPOSED body with two `Reduce { }` closures
// (the isowords `Settings.body` shape). Discovery emits two
// `MultiReduceFeature.body` candidates; the cycle-133 verify-path dedup
// resolves them to one (pre-133 this surveyed as measured-error /
// ambiguousPin). The witness verifies the whole composed body. `dismiss`
// is the idempotent witness.
@Reducer
struct MultiReduceFeature {
    @ObservableState
    struct State: Equatable {
        var sheet = false
        var count = 0
    }

    enum Action {
        case present   // driver — sheet = true
        case dismiss   // idempotent witness — sheet = false
        case tick      // driver — count += 1 (bounded by sequence length)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .present:
                state.sheet = true
                return .none
            case .dismiss:
                state.sheet = false
                return .none
            case .tick:
                return .none
            }
        }
        Reduce { state, action in
            switch action {
            case .tick:
                state.count += 1
                return .none
            case .present, .dismiss:
                return .none
            }
        }
    }
}
