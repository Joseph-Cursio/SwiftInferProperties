import ComposableArchitecture
import Foundation

// Cycle 142 — biconditional verify corpus widening, fixture 4 of 5: the
// literal-inferred-Bool full-coverage overrule proof.
//
// The original trio annotates its Bool flags explicitly (`var isActive:
// Bool = false`). This reducer uses the V1.97 LITERAL-INFERENCE shape —
// `var isRefreshing = false` with no `: Bool` annotation — that the
// detector recovers from the `false` initializer. Also widens the optional
// type to `String?` (vs the trio's `Int?`) and the Bool pattern to
// "Refreshing". The reducer keeps `isRefreshing == (feed != nil)` in sync,
// all Action cases payload-free → FULL-coverage `measured-bothPass` → the
// Finding-G pin is OVERRULED → `.verified`.
//
// One Bool-flag × one Optional (and `isRefreshing` is not a cardinality
// `Showing`/`Presenting` pattern) → biconditional only.
@Reducer
struct FeedFeature {
    @ObservableState
    struct State: Equatable {
        var isRefreshing = false      // literal-inferred Bool (V1.97 path)
        var feed: String?
    }

    enum Action {
        case load
        case unload
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .load:
                state.feed = "data"
                state.isRefreshing = true     // active iff feed present — in sync
                return .none
            case .unload:
                state.feed = nil
                state.isRefreshing = false    // inactive iff feed nil — in sync
                return .none
            }
        }
    }
}
