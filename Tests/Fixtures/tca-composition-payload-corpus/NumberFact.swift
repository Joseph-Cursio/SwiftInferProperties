// Composition-payload measured corpus, slice 2 — a self-contained TCA reducer
// whose Action carries a `Result<String, any Error>` payload (no custom
// DependencyKey, so it co-compiles against CA alone). Curated in the spirit of
// the tca-examples-measured-corpus. The verifier explores
// `Action.response(.failure(CancellationError()))` — a canned type-erased error,
// no `Gen<String>` needed — driving the reducer's failure branch. Original
// shape derived from Point-Free's Effects-Basics example; MIT, Point-Free, Inc.
import ComposableArchitecture

@Reducer
struct NumberFact {
    @ObservableState
    struct State: Equatable {
        var text = ""
        var isLoading = false
    }

    enum Action {
        case load
        case response(Result<String, any Error>)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .load:
                state.isLoading = true
                return .none
            case .response(.success(let value)):
                state.isLoading = false
                state.text = value
                return .none
            case .response(.failure):
                // Failure leaves the text untouched, just clears the flag — a
                // deterministic transition the verifier drives via `.dismiss`'s
                // Result analogue, `.failure(CancellationError())`.
                state.isLoading = false
                return .none
            }
        }
    }
}
