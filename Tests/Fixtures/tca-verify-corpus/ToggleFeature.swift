import ComposableArchitecture

// C2 widening (cycle 130) — real `@Reducer`, all-payload-free (Phase A).
// Demonstrates that execution catches an EXACT-witness false positive, not
// only `set*` ones: `hide` is an exact idempotence witness by name but its
// body TOGGLES (so applying it twice ≠ once → not idempotent). Mirror of
// `EditorFeature.setBadge` (a `set*` false positive) — the name-vs-behavior
// mismatch is exactly what measured execution exists to catch. `select` is a
// genuine TRUE-positive witness in the same reducer.
@Reducer
struct ToggleFeature {
    @ObservableState
    struct State: Equatable {
        var index = 0
        var menu = false
    }

    enum Action {
        case advance   // driver — index += 1 (bounded by sequence length)
        case select    // idempotent witness — index = 0 (TRUE positive)
        case hide      // exact witness by name, FALSE positive — toggles
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
            case .hide:
                state.menu.toggle()
                return .none
            }
        }
    }
}
