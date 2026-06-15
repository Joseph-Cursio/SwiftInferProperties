import ComposableArchitecture
import Foundation

// Cycle 136 — cardinality verify corpus, fixture 3 of 3: the FALSE
// POSITIVE (the cardinality analogue of the idempotence corpus's
// `setBadge`).
//
// State has two presentation Bool flags (`isShowingBanner`,
// `isPresentingToast`) → a CardinalityWitness fires statically: the
// both-active state is *representable*, so the detector emits the
// `Σ indicators <= 1` suggestion. But the reducer does NOT enforce the
// mutex — `raiseBanner` and `raiseToast` each set their own flag without
// clearing the other, so the sequence [raiseBanner, raiseToast] drives
// both true (Σ = 2). The per-step precondition traps → `measured-
// defaultFails` → suppressed. Only execution disproves the static smell.
//
// All cases are payload-free (full coverage), so this is a clean
// defaultFails — the coverage gate is moot for a disproven invariant.
@Reducer
struct LeakyFeature {
    @ObservableState
    struct State: Equatable {
        var isShowingBanner: Bool = false
        var isPresentingToast: Bool = false
    }

    enum Action {
        case raiseBanner
        case raiseToast
        case clearAll
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .raiseBanner:
                state.isShowingBanner = true   // BUG (deliberate): does not clear the toast
                return .none
            case .raiseToast:
                state.isPresentingToast = true  // BUG (deliberate): does not clear the banner
                return .none
            case .clearAll:
                state.isShowingBanner = false
                state.isPresentingToast = false
                return .none
            }
        }
    }
}
