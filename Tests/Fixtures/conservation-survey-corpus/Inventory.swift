// Cycle 134 — verify-ready conservation survey corpus, fixture 1 of 2.
//
// A genuinely count-conserving reducer. State pairs a count-shaped Int
// aggregate (`count`) with an array collection (`items`) — the
// ConservationWitness shape (PRD §5.2): the detector emits
// `state.count == state.items.count`. Every Action transition keeps the
// two in lockstep, so the invariant holds at `State()` (0 == 0) and after
// every action — a `measured-bothPass`. All Action cases are payload-free,
// so `Action` is `CaseIterable` and the reducer satisfies the verify
// stub's shape (zero-arg `Equatable` State, `(State, Action) -> State`).
//
// `clearAll` is NOT an idempotence witness — the exact witness set holds
// "clear", not "clearAll" (no prefix match either), so the only family
// this fixture surfaces is conservation.

public struct InventoryReducer {
    public struct State: Equatable, Sendable {
        public var count: Int
        public var items: [Int]
        public init(count: Int = 0, items: [Int] = []) {
            self.count = count
            self.items = items
        }
    }

    public enum Action: CaseIterable, Sendable {
        case addItem
        case removeLast
        case clearAll
    }

    public static func reduce(_ s: State, _ a: Action) -> State {
        switch a {
        case .addItem:
            // Append AND bump the count together — invariant preserved.
            return State(count: s.count + 1, items: s.items + [s.items.count])
        case .removeLast:
            guard !s.items.isEmpty else { return s }
            return State(count: s.count - 1, items: Array(s.items.dropLast()))
        case .clearAll:
            return State(count: 0, items: [])
        }
    }
}
