// Cycle 134 — verify-ready conservation survey corpus, fixture 2 of 2.
//
// The deliberate conservation FALSE POSITIVE — the analogue of the
// idempotence corpus's `SettingsReducer.setBadge`. State pairs a
// count-shaped Int (`badgeCount`) with an array (`notifications`), so the
// ConservationWitness forms and the static detector emits the suggestion
// `state.badgeCount == state.notifications.count`. But the `.receive`
// transition bumps `badgeCount` WITHOUT appending to `notifications`, so
// the count drifts ahead of the array: after one `.receive`, badgeCount=1
// while notifications.count=0. Only *execution* disproves the name-shaped
// suggestion — the per-step precondition traps → `measured-defaultFails` →
// suppressed (never promoted past `.possible`).

public struct BadgeReducer {
    public struct State: Equatable, Sendable {
        public var badgeCount: Int
        public var notifications: [Int]
        public init(badgeCount: Int = 0, notifications: [Int] = []) {
            self.badgeCount = badgeCount
            self.notifications = notifications
        }
    }

    public enum Action: CaseIterable, Sendable {
        case receive
        case markAllRead
    }

    public static func reduce(_ s: State, _ a: Action) -> State {
        switch a {
        case .receive:
            // BUG (deliberate): bumps the badge but forgets to append the
            // notification — `badgeCount` drifts ahead of `notifications`.
            return State(badgeCount: s.badgeCount + 1, notifications: s.notifications)
        case .markAllRead:
            return State(badgeCount: 0, notifications: [])
        }
    }
}
