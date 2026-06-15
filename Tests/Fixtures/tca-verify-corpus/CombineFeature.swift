import ComposableArchitecture
import Foundation

// Cycle 144 — tca-verify-corpus widening: the CombineReducers composed body.
//
// Cycle 133 demonstrated composed bodies via a bare two-`Reduce` body
// (MultiReduceFeature) and a `Scope` composition (ParentFeature). This adds
// the explicit `CombineReducers { … }` operator — the remaining composition
// shape called out in cycle 131. The walker emits one candidate per inner
// `Reduce` closure (same qualifiedName); the cycle-133 dedup collapses them
// so the whole composed body is verified via `CombineFeature().reduce`. The
// payload-free `dismiss` witness clears both flags → applying it twice
// equals once → `measured-bothPass` (full coverage).
@Reducer
struct CombineFeature {
    @ObservableState
    struct State: Equatable {
        var a = false
        var b = false
    }

    enum Action {
        case dismiss
        case bump
    }

    var body: some Reducer<State, Action> {
        CombineReducers {
            Reduce { state, action in
                switch action {
                case .dismiss:
                    state.a = false
                    return .none
                case .bump:
                    state.a = true
                    return .none
                }
            }
            Reduce { state, action in
                switch action {
                case .dismiss:
                    state.b = false
                    return .none
                case .bump:
                    state.b = true
                    return .none
                }
            }
        }
    }
}
