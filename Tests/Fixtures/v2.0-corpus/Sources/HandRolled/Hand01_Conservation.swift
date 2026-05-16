// V1.90 hand-rolled v2.0 calibration corpus — fixture 01.
//
// **Family**: Conservation (PRD §5.2).
// **Witness**: stored Int aggregate whose name contains `count`
// (case-insensitive) + an array collection `[T]` in the same State.
// **Carrier**: generic (method on a struct).
//
// Expected witnesses: 1 (itemCount × items pair).
// Other families: should not fire on this State.

struct CountedListReducer {
    struct State {
        var itemCount: Int
        var items: [String]
    }
    enum Action {
        case add(String)
        case noop
    }
    static func reduce(_ state: State, _ action: Action) -> State {
        var next = state
        switch action {
        case .add(let value):
            next.items.append(value)
            next.itemCount = next.items.count
        case .noop:
            break
        }
        return next
    }
}
