import ComposableArchitecture
import Foundation

// Cycle 137 — biconditional verify corpus, fixture 1 of 3: the
// FULL-COVERAGE pin-overrule proof.
//
// State pairs a biconditional-shaped Bool flag (`isActive`) with an
// Optional (`token`) → a BiconditionalWitness (`state.isActive ==
// (state.token != nil)`). The reducer keeps the pair genuinely in sync:
// `isActive` is true exactly when `token` is non-nil. Every Action case is
// payload-free → the verifier explores the FULL action space (0 excluded).
// The biconditional holds at `State()` (false == nil-is-nil) and after every
// action → a full-coverage `measured-bothPass`.
//
// Per the cycle-135/136 rule, a full-coverage bothPass on a gated family
// OVERRULES the Finding-G pin (the reducer provably keeps the pair in sync
// with no view layer in the loop) → promotes `.possible → .verified`.
//
// `isActive` matches the biconditional Bool pattern "Active" but NOT
// cardinality's "Showing"/"Presenting", and `token` matches no cardinality
// Optional pattern — so the only family this reducer surfaces is
// biconditional. Action names avoid the idempotence witness vocabulary.
@Reducer
struct SessionFeature {
    @ObservableState
    struct State: Equatable {
        var isActive: Bool = false
        var token: Int?
    }

    enum Action {
        case begin
        case end
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .begin:
                state.token = 100
                state.isActive = true     // active iff token present — in sync
                return .none
            case .end:
                state.token = nil
                state.isActive = false    // inactive iff token nil — in sync
                return .none
            }
        }
    }
}
