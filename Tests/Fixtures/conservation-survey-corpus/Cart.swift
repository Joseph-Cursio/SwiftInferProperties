// Cycle 140 — conservation survey corpus widening, fixture 3 of 4.
//
// A second genuinely-conserving reducer, exercising a DIFFERENT maintenance
// mechanism than InventoryReducer: instead of bumping the count in lockstep
// (`count += 1`), every transition RECOMPUTES the aggregate from the
// collection (`itemCount = lineItems.count`). The ConservationWitness
// `state.itemCount == state.lineItems.count` holds at `State()` and after
// every action → `measured-bothPass`. Also widens the witness vocabulary
// (`itemCount` / `lineItems` vs `count` / `items`).

public struct CartReducer {
    public struct State: Equatable, Sendable {
        public var itemCount: Int
        public var lineItems: [Int]
        public init(itemCount: Int = 0, lineItems: [Int] = []) {
            self.itemCount = itemCount
            self.lineItems = lineItems
        }
    }

    public enum Action: CaseIterable, Sendable {
        case addLine
        case dropLine
        case empty
    }

    public static func reduce(_ s: State, _ a: Action) -> State {
        var st = s
        switch a {
        case .addLine:
            st.lineItems.append(st.lineItems.count)
            st.itemCount = st.lineItems.count   // recompute, not increment
        case .dropLine:
            if !st.lineItems.isEmpty { st.lineItems.removeLast() }
            st.itemCount = st.lineItems.count
        case .empty:
            st.lineItems = []
            st.itemCount = st.lineItems.count
        }
        return st
    }
}
