// Phase 2 (Redux) — determinism verify corpus, fixture 1 of 2.
//
// A genuinely deterministic `(State, Action) -> State` reducer: every
// transition is a pure function of its inputs, so applying the same
// (state, action) twice yields equal results. Determinism holds at
// `State()` and after every action → a `measured-bothPass`, promoted
// `.possible → .verified`.
//
// Zero-arg `Equatable` State + payload-free `CaseIterable` Action satisfy
// the verify stub's shape.

public struct PureCounterReducer {
    public struct State: Equatable, Sendable {
        public var count: Int
        public init(count: Int = 0) {
            self.count = count
        }
    }

    public enum Action: CaseIterable, Sendable {
        case increment
        case decrement
        case zero
    }

    public static func reduce(_ state: State, _ action: Action) -> State {
        switch action {
        case .increment:
            return State(count: state.count + 1)
        case .decrement:
            return State(count: state.count - 1)
        case .zero:
            return State(count: 0)
        }
    }
}
