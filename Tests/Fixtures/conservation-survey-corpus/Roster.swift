// Cycle 140 — conservation survey corpus widening, fixture 4 of 4.
//
// A second conservation FALSE POSITIVE, with a DIFFERENT bug shape than
// BadgeReducer. Badge increments the count WITHOUT appending; Roster keeps
// the pair in lockstep on `join` but `leaveAll` clears the collection
// WITHOUT resetting the count — a clear-without-reset desync. The
// ConservationWitness `state.memberCount == state.members.count` forms
// statically, but the sequence [join, leaveAll] leaves `memberCount` > 0
// with `members` empty → the per-step precondition traps →
// `measured-defaultFails` → suppressed. Only execution disproves it.

public struct RosterReducer {
    public struct State: Equatable, Sendable {
        public var memberCount: Int
        public var members: [Int]
        public init(memberCount: Int = 0, members: [Int] = []) {
            self.memberCount = memberCount
            self.members = members
        }
    }

    public enum Action: CaseIterable, Sendable {
        case join
        case leaveAll
    }

    public static func reduce(_ s: State, _ a: Action) -> State {
        var st = s
        switch a {
        case .join:
            st.members.append(st.members.count)
            st.memberCount += 1                  // in lockstep — fine
        case .leaveAll:
            st.members.removeAll()               // BUG (deliberate): forgets to reset memberCount
        }
        return st
    }
}
