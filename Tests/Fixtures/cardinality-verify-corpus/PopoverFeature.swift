import ComposableArchitecture
import Foundation

// Cycle 141 — cardinality verify corpus widening, fixture 5 of 5: a
// THREE-field Optional-presentation FALSE POSITIVE.
//
// State has THREE Optional presentation fields (`activeSheet`,
// `activeAlert`, `activePopover`) → a single CardinalityWitness summing
// three `!= nil` indicators (`… <= 1`) — exercising both the richer
// ≥3-field witness shape and the Optional indicator in the defaultFails
// path (LeakyFeature is an all-Bool false positive). The reducer does NOT
// enforce the mutex — each `open*` sets its own field without clearing the
// others — so [openSheet, openAlert] drives two fields non-nil (Σ = 2) →
// the per-step precondition traps → `measured-defaultFails` → suppressed.
//
// All payload-free (full coverage), so the coverage gate is moot for a
// disproven invariant. Three Optionals, no Bool → cardinality only.
@Reducer
struct PopoverFeature {
    @ObservableState
    struct State: Equatable {
        var activeSheet: Int?
        var activeAlert: Int?
        var activePopover: Int?
    }

    enum Action {
        case openSheet
        case openAlert
        case openPopover
        case closeAll
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .openSheet:
                state.activeSheet = 1     // BUG (deliberate): does not clear the others
                return .none
            case .openAlert:
                state.activeAlert = 1
                return .none
            case .openPopover:
                state.activePopover = 1
                return .none
            case .closeAll:
                state.activeSheet = nil
                state.activeAlert = nil
                state.activePopover = nil
                return .none
            }
        }
    }
}
