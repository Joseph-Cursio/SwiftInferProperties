import ComposableArchitecture
import Foundation

// Cycle 136 — cardinality verify corpus, fixture 1 of 3: the
// FULL-COVERAGE pin-overrule proof.
//
// State has two presentation-shaped Bool flags (`isShowingSheet`,
// `isPresentingAlert`) → a CardinalityWitness (`Σ indicators <= 1`). The
// reducer ENFORCES the mutex itself: opening one presentation clears the
// other, so at most one is ever active. Every Action case is payload-free
// → the verifier explores the FULL action space (0 excluded). The mutex
// holds at `State()` (0 active) and after every action → a full-coverage
// `measured-bothPass`.
//
// Per the cycle-135 decision, a full-coverage bothPass OVERRULES the
// Finding-G `.possible` pin (the reducer provably enforces the mutex with
// no UI layer in the loop) → promotes `.possible → .verified`.
//
// Action names deliberately avoid the idempotence witness vocabulary
// (`open*` / `closeAll` are neither exact nor prefix witnesses), so the
// only family this reducer surfaces is cardinality.
@Reducer
struct RouterFeature {
    @ObservableState
    struct State: Equatable {
        var isShowingSheet: Bool = false
        var isPresentingAlert: Bool = false
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
                state.isShowingSheet = true
                state.isPresentingAlert = false   // enforce the mutex
                return .none
            case .openAlert:
                state.isPresentingAlert = true
                state.isShowingSheet = false       // enforce the mutex
                return .none
            case .closeAll:
                state.isShowingSheet = false
                state.isPresentingAlert = false
                return .none
            }
        }
    }
}
