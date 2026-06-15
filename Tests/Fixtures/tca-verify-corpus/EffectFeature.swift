import ComposableArchitecture

// C2 widening (cycle 131) — real `@Reducer` whose body returns real
// `Effect`s (`.run { … }`), not just `.none`. Exercises the verifier's
// effect-discard posture (PRD §16 #1): the returned Effect is captured and
// thrown away; only State is checked. `close` is the idempotent witness;
// `refresh` returns an effect that the verifier never runs.
@Reducer
struct EffectFeature {
    @ObservableState
    struct State: Equatable {
        var menu = false
        var count = 0
    }

    enum Action {
        case refresh   // driver — mutates State AND returns an effect (discarded)
        case close     // idempotent witness — menu = false
        case tick      // driver — count += 1 (bounded by sequence length)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .refresh:
                state.count = 0
                return .run { _ in /* effect — captured + discarded by the verifier */ }
            case .close:
                state.menu = false
                return .none
            case .tick:
                state.count += 1
                return .none
            }
        }
    }
}
