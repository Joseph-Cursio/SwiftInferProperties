// Multi-module discovery fixture, module Beta. Shares its type, State, and
// Action names with `Alpha/CounterReducer.swift` — same-named reducers in two
// modules. Without module tagging the two collapse to one candidate (dedupe by
// State+Action); tagged by module they stay distinct and a `Beta.…` pin selects
// only this one.
public struct CounterReducer {
    public struct State: Equatable, Sendable {
        public var count: Int
        public init(count: Int = 0) {
            self.count = count
        }
    }

    public enum Action: CaseIterable, Sendable {
        case increment
        case decrement
    }

    public static func reduce(_ state: State, _ action: Action) -> State {
        switch action {
        case .increment:
            return State(count: state.count + 1)
        case .decrement:
            return State(count: state.count - 1)
        }
    }
}
