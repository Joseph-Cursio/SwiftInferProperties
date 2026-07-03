// TCA determinism corpus, fixture 2 of 3 — nondeterminism routed PROPERLY
// through @Dependency. The verifier pins `\.uuid` to a constant, so both
// applications get the same UUID → state equal → measured-bothPass →
// verified. This is the point: declared dependencies are fine.
import ComposableArchitecture
import Foundation

@Reducer
struct ProperDependencyFeature {
    @ObservableState
    struct State: Equatable {
        var lastID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    }
    enum Action {
        case generate
    }
    @Dependency(\.uuid) var uuid
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .generate:
                state.lastID = self.uuid()   // via @Dependency — pinned → deterministic
            }
            return .none
        }
    }
}
