// Cycle 115 — verify-ready idempotence survey corpus, fixture 1 of 3.
//
// Navigation-style reducer. Exact-match curated idempotence witnesses:
// `dismiss`, `close`, `hide` — each clears one presentation flag, so
// applying twice equals applying once. `present` is a non-witness driver
// (exactly "present" → no prefix match; not in the exact set) that varies
// state. All Action cases are payload-free, so `Action` is `CaseIterable`
// and the reducer satisfies the verify stub's shape.

public struct NavigationReducer {
    public struct State: Equatable, Sendable {
        public var sheet: Bool
        public var alert: Bool
        public var menu: Bool
        public init(sheet: Bool = false, alert: Bool = false, menu: Bool = false) {
            self.sheet = sheet
            self.alert = alert
            self.menu = menu
        }
    }

    public enum Action: CaseIterable, Sendable {
        case present
        case dismiss
        case close
        case hide
    }

    public static func reduce(_ s: State, _ a: Action) -> State {
        switch a {
        case .present: return State(sheet: true, alert: s.alert, menu: s.menu)
        case .dismiss: return State(sheet: false, alert: s.alert, menu: s.menu)
        case .close: return State(sheet: s.sheet, alert: false, menu: s.menu)
        case .hide: return State(sheet: s.sheet, alert: s.alert, menu: false)
        }
    }
}
