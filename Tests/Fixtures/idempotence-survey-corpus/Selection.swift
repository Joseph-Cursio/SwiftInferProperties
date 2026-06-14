// Cycle 115 — verify-ready idempotence survey corpus, fixture 2 of 3.
//
// Selection-style reducer covering the prefix arm of the witness
// vocabulary alongside an exact match: `select` (exact), `selectFirst`
// (prefix `select*`), and `showDetail` (prefix `show*`). Each drives state
// to a fixed point (index 0 / detail shown), so applying twice equals
// applying once. `advance` is a non-witness driver. Payload-free actions →
// `CaseIterable`.

public struct SelectionReducer {
    public struct State: Equatable, Sendable {
        public var index: Int
        public var detail: Bool
        public init(index: Int = 0, detail: Bool = false) {
            self.index = index
            self.detail = detail
        }
    }

    public enum Action: CaseIterable, Sendable {
        case advance
        case select
        case selectFirst
        case showDetail
    }

    public static func reduce(_ s: State, _ a: Action) -> State {
        switch a {
        case .advance: return State(index: s.index + 1, detail: s.detail)
        case .select: return State(index: 0, detail: s.detail)
        case .selectFirst: return State(index: 0, detail: s.detail)
        case .showDetail: return State(index: s.index, detail: true)
        }
    }
}
