// TCA determinism corpus, fixture 3 of 3 — the anti-pattern this catches.
// A raw `UUID()` in the state mutation BYPASSES @Dependency, so even with
// `\.uuid` pinned the two applications get different UUIDs → state differs
// → measured-defaultFails → suppressed. A true negative: the reducer really
// isn't deterministic, and it should have used @Dependency(\.uuid).
import ComposableArchitecture
import Foundation

@Reducer
struct SnuckRawFeature {
    @ObservableState
    struct State: Equatable {
        var lastID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    }
    enum Action {
        case generate
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .generate:
                state.lastID = UUID()   // RAW — bypasses @Dependency → nondeterministic
            }
            return .none
        }
    }
}
