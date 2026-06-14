// Cycle 115 — verify-ready idempotence survey corpus, fixture 3 of 3.
//
// **Carries one deliberate false positive — the campaign's whole point.**
// `setBadge` matches the `set*` idempotence-witness prefix (the name
// suggests "set to a fixed value"), so the static detector emits an
// idempotence suggestion for it. But the body *increments* a counter, so
// applying twice ≠ once: the property is false. Static analysis can't tell
// a fixed-value setter from an accumulating one — only execution can. The
// survey's `measured-defaultFails` on this identity is exactly the
// execution-gates-promotion signal the A1 campaign is built on.
//
// `cancel` is a genuine exact-match idempotent witness for contrast
// (sets a flag true, idempotent). `tick` is a non-witness driver.

public struct SettingsReducer {
    public struct State: Equatable, Sendable {
        public var cancelled: Bool
        public var badge: Int
        public init(cancelled: Bool = false, badge: Int = 0) {
            self.cancelled = cancelled
            self.badge = badge
        }
    }

    public enum Action: CaseIterable, Sendable {
        case tick
        case cancel
        case setBadge
    }

    public static func reduce(_ s: State, _ a: Action) -> State {
        switch a {
        case .tick: return State(cancelled: s.cancelled, badge: s.badge + 1)
        case .cancel: return State(cancelled: true, badge: s.badge)
        // Deliberately non-idempotent despite the `set*` name.
        case .setBadge: return State(cancelled: s.cancelled, badge: s.badge + 1)
        }
    }
}
