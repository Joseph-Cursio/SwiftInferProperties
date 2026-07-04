// Multi-module discovery fixture, module Alpha. Deliberately shares its type,
// State, and Action names with `Beta/CounterReducer.swift` so the two are
// indistinguishable except by module — the cross-module disambiguation case.
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
