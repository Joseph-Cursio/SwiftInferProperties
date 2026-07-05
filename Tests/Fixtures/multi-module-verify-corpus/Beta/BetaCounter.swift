// M3 multi-module measured-verify fixture, module Beta. Sibling to Alpha's
// reducer (see AlphaCounter.swift). Distinct type/field names + a Beta-only
// helper (`BetaConstants`) so that if verify built this reducer against Alpha's
// product (a per-module-resolution bug) the missing `BetaCounter`/`BetaConstants`
// symbols would fail the build — proving the survey resolved module Beta's own
// product. Pure and deterministic → determinism family verifies `bothPass`.
public struct BetaCounter {
    public struct State: Equatable, Sendable {
        public var value: Int
        public init(value: Int = 0) { self.value = value }
    }

    public enum Action: CaseIterable, Sendable {
        case tick
        case clear
    }

    public static func reduce(_ state: State, _ action: Action) -> State {
        switch action {
        case .tick:
            return State(value: state.value + BetaConstants.delta)
        case .clear:
            return State(value: 0)
        }
    }
}

enum BetaConstants {
    static let delta = 1
}
