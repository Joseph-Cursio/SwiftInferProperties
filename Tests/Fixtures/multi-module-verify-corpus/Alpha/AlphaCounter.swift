// M3 multi-module measured-verify fixture, module Alpha. A plain-Swift
// `(State, Action) -> State` reducer (generic/redux carrier — no TCA dep), so
// verify uses the path-dependency workdir and resolves module Alpha's library
// product. Distinct type/field names from Beta's reducer (so their identities
// don't collide) plus an Alpha-only helper (`AlphaConstants`) so building this
// reducer against the *wrong* module's product would fail to compile — the
// test's guard that per-module product resolution actually happened. Pure and
// deterministic, so the determinism family verifies `bothPass`.
public struct AlphaCounter {
    public struct State: Equatable, Sendable {
        public var count: Int
        public init(count: Int = 0) { self.count = count }
    }

    public enum Action: CaseIterable, Sendable {
        case increment
        case reset
    }

    public static func reduce(_ state: State, _ action: Action) -> State {
        switch action {
        case .increment:
            return State(count: state.count + AlphaConstants.step)
        case .reset:
            return State(count: 0)
        }
    }
}

enum AlphaConstants {
    static let step = 1
}
