import ComposableArchitecture
import Foundation

// Cycle 137 — biconditional verify corpus, fixture 2 of 3: the
// PARTIAL-COVERAGE coverage-gate proof.
//
// Same shape as SessionFeature (a biconditional Bool flag `isFetching`
// kept in sync with an Optional `payload`), so the invariant
// `state.isFetching == (state.payload != nil)` genuinely holds →
// `measured-bothPass`. The difference: the Action enum carries one
// NON-constructible case — `received(Data)` (Data is not a recognized raw
// type) — which the relaxed exploration EXCLUDES. So the verify run is
// PARTIAL coverage (`excludedActionCount == 1`).
//
// Per the cycle-135/136 rule, a *partial* bothPass does NOT overrule the
// Finding-G pin — the failure mode lives in exactly the excluded
// composition actions, so partial coverage is biased toward false-pass.
// This reducer therefore stays `.possible` despite its bothPass: the proof
// that the overrule is gated on coverage, not on the bothPass alone.
@Reducer
struct ConnectionFeature {
    @ObservableState
    struct State: Equatable {
        var isFetching: Bool = false
        var payload: Int?
    }

    enum Action {
        case open
        case shutdown
        case received(Data)   // non-constructible payload → excluded → partial coverage
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .open:
                state.payload = 7
                state.isFetching = true    // fetching iff payload present — in sync
                return .none
            case .shutdown:
                state.payload = nil
                state.isFetching = false   // idle iff payload nil — in sync
                return .none
            case .received:
                // Excluded from exploration; its body never runs in verify.
                return .none
            }
        }
    }
}
