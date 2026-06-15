import ComposableArchitecture

// C2 (cycle 127) — a verify-ready REAL TCA reducer: `@Reducer` +
// `@ObservableState`, self-contained (no Views / cross-file refs / UIKit),
// payload-free Action with proven idempotence witnesses (dismiss/close/hide
// are exact-match witnesses). All-payload-free → Phase A full exploration.
@Reducer
struct NavFeature {
    @ObservableState
    struct State: Equatable {
        var sheet = false
        var alert = false
        var menu = false
    }

    enum Action {
        case present   // driver — sets sheet true
        case dismiss   // idempotent witness — sheet = false
        case close     // idempotent witness — alert = false
        case hide      // idempotent witness — menu = false
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
            case .close:
                state.alert = false
                return .none
            case .hide:
                state.menu = false
                return .none
            }
        }
    }
}
