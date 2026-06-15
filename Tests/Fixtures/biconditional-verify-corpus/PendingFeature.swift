import ComposableArchitecture
import Foundation

// Cycle 142 — biconditional verify corpus widening, fixture 5 of 5: a
// false positive with the INVERSE drift direction.
//
// StaleFeature drifts the flag ahead of the optional (`isLoading = true`
// while `data` is nil). This reducer drifts the OTHER way — `.receive` sets
// the optional WITHOUT setting the flag (`nextPage = 5` while
// `isFetchingMore` stays false), and `.beginFetch` sets the flag without the
// optional. Either direction violates `state.isFetchingMore ==
// (state.nextPage != nil)` → the per-step precondition traps →
// `measured-defaultFails` → suppressed. Only execution disproves the static
// smell.
//
// All cases payload-free (full coverage). One Bool-flag × one Optional →
// biconditional only.
@Reducer
struct PendingFeature {
    @ObservableState
    struct State: Equatable {
        var isFetchingMore: Bool = false
        var nextPage: Int?
    }

    enum Action {
        case beginFetch
        case receive
        case finish
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .beginFetch:
                state.isFetchingMore = true    // BUG: flag set, nextPage still nil
                return .none
            case .receive:
                state.nextPage = 5             // BUG: optional set, flag still false
                return .none
            case .finish:
                state.isFetchingMore = false
                state.nextPage = nil
                return .none
            }
        }
    }
}
