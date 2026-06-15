import ComposableArchitecture
import Foundation

// Cycle 137 — biconditional verify corpus, fixture 3 of 3: the FALSE
// POSITIVE (the biconditional analogue of the cardinality corpus's
// LeakyFeature / the idempotence corpus's setBadge).
//
// State pairs a biconditional Bool flag (`isLoading`) with an Optional
// (`data`) → a BiconditionalWitness fires statically: the flag-without-
// result state is *representable*, so the detector emits `state.isLoading
// == (state.data != nil)`. But the reducer drifts the pair out of sync —
// `.load` sets `isLoading = true` while `data` is still nil (the classic
// "loading flag set before the result arrives" shape biconditional is
// pinned for). After `.load`: isLoading=true, data=nil → the per-step
// precondition traps → `measured-defaultFails` → suppressed. Only execution
// disproves the static smell.
//
// All cases are payload-free (full coverage), so this is a clean
// defaultFails — the coverage gate is moot for a disproven invariant.
@Reducer
struct StaleFeature {
    @ObservableState
    struct State: Equatable {
        var isLoading: Bool = false
        var data: Int?
    }

    enum Action {
        case load
        case arrive
        case wipe
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .load:
                // BUG (deliberate): sets the flag before the result arrives —
                // isLoading=true while data is still nil → drift.
                state.isLoading = true
                return .none
            case .arrive:
                state.data = 1
                return .none
            case .wipe:
                state.isLoading = false
                state.data = nil
                return .none
            }
        }
    }
}
