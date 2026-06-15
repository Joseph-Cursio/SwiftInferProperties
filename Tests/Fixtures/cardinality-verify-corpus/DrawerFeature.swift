import ComposableArchitecture
import Foundation

// Cycle 136 — cardinality verify corpus, fixture 2 of 3: the
// PARTIAL-COVERAGE coverage-gate proof.
//
// Same shape as RouterFeature (two presentation Bool flags, mutex enforced
// by the reducer), so the cardinality invariant `Σ indicators <= 1`
// genuinely holds → `measured-bothPass`. The difference: the Action enum
// carries one NON-constructible case — `received(Data)` (Data is not a
// recognized raw type) — which the relaxed exploration EXCLUDES. So the
// verify run is PARTIAL coverage (`excludedActionCount == 1`).
//
// Per the cycle-135 decision, a *partial* bothPass does NOT overrule the
// Finding-G pin — the failure mode lives in exactly the excluded
// composition actions, so partial coverage is biased toward false-pass.
// This reducer therefore stays `.possible` despite its bothPass: the proof
// that the overrule is gated on coverage, not on the bothPass alone.
@Reducer
struct DrawerFeature {
    @ObservableState
    struct State: Equatable {
        var isShowingMenu: Bool = false
        var isPresentingPopover: Bool = false
    }

    enum Action {
        case openMenu
        case openPopover
        case closeAll
        case received(Data)   // non-constructible payload → excluded → partial coverage
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .openMenu:
                state.isShowingMenu = true
                state.isPresentingPopover = false
                return .none
            case .openPopover:
                state.isPresentingPopover = true
                state.isShowingMenu = false
                return .none
            case .closeAll:
                state.isShowingMenu = false
                state.isPresentingPopover = false
                return .none
            case .received:
                // Excluded from exploration; its body never runs in verify.
                return .none
            }
        }
    }
}
