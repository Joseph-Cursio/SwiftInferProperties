import ComposableArchitecture

// C2 widening (cycle 133) — a `Scope` composition. `ParentFeature.body`
// composes a child reducer via `Scope(state:action:)` plus its own `Reduce`.
// Exercises: composed-body discovery + the child-action case
// (`child(ChildFeature.Action)`) being Phase B non-derivable → excluded
// (disclosure "excluded: child"), while the parent witness verifies the
// whole composed body (Scope + Reduce) via `ParentFeature().reduce`. The
// child is co-compiled and surveyed independently (its own `close` witness).

@Reducer
struct ChildFeature {
    @ObservableState
    struct State: Equatable {
        var menu = false
    }

    enum Action {
        case open    // driver — menu = true
        case close   // idempotent witness — menu = false
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .open:
                state.menu = true
                return .none
            case .close:
                state.menu = false
                return .none
            }
        }
    }
}

@Reducer
struct ParentFeature {
    @ObservableState
    struct State: Equatable {
        var dialog = false
        var child = ChildFeature.State()
    }

    enum Action {
        case present                     // driver — dialog = true
        case dismiss                     // idempotent witness — dialog = false
        case child(ChildFeature.Action)  // non-derivable — excluded
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.child, action: \.child) {
            ChildFeature()
        }
        Reduce { state, action in
            switch action {
            case .present:
                state.dialog = true
                return .none
            case .dismiss:
                state.dialog = false
                return .none
            case .child:
                return .none
            }
        }
    }
}
