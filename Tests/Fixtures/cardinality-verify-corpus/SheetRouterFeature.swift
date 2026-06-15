import ComposableArchitecture
import Foundation

// Cycle 141 — cardinality verify corpus widening, fixture 4 of 5: the
// OPTIONAL-PRESENTATION full-coverage overrule proof.
//
// The original trio (Router/Drawer/Leaky) uses only Bool-flag fields, whose
// indicator is `state.<name>`. This reducer uses two OPTIONAL-presentation
// fields (`activeSheet`, `activeAlert` — names matching the `sheet` / `alert`
// patterns), whose indicator is `state.<name> != nil` — exercising the
// other half of the `Σ indicators <= 1` predicate vocabulary. The reducer
// enforces the mutex (opening one nils the other), all Action cases are
// payload-free → FULL-coverage `measured-bothPass` → the Finding-G pin is
// OVERRULED → `.verified`.
//
// Two Optionals and no Bool flag → cardinality only (a Bool + Optional pair
// would also surface biconditional; two Optionals don't).
@Reducer
struct SheetRouterFeature {
    @ObservableState
    struct State: Equatable {
        var activeSheet: Int?
        var activeAlert: Int?
    }

    enum Action {
        case openSheet
        case openAlert
        case closeAll
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .openSheet:
                state.activeSheet = 1
                state.activeAlert = nil      // enforce the mutex
                return .none
            case .openAlert:
                state.activeAlert = 1
                state.activeSheet = nil       // enforce the mutex
                return .none
            case .closeAll:
                state.activeSheet = nil
                state.activeAlert = nil
                return .none
            }
        }
    }
}
