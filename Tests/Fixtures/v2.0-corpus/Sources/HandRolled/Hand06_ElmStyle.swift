// V1.90 hand-rolled v2.0 calibration corpus — fixture 06.
//
// **Carrier-kind coverage**: elm-style free function (top-level
// `func reduce(_:_:)` rather than a struct method). M1.C.1
// differentiates `.elmStyle` from `.generic` — without this
// fixture the hand-rolled corpus would be 100% `.generic`.
//
// **Families**: Idempotence (refresh action) + Cardinality (two
// Showing flags) — small mix demonstrating that family detection
// is carrier-agnostic.
//
// Expected witnesses: 1 idempotence (refresh) + 1 cardinality
// (isShowingMenu × isShowingHelp).

struct CounterState {
    var value: Int
    var isShowingMenu: Bool
    var isShowingHelp: Bool
}

enum CounterAction {
    case increment
    case decrement
    case refresh
    case toggleMenu
}

func reduce(_ state: CounterState, _ action: CounterAction) -> CounterState {
    var next = state
    switch action {
    case .increment: next.value += 1
    case .decrement: next.value -= 1
    case .refresh: next = CounterState(value: 0, isShowingMenu: false, isShowingHelp: false)
    case .toggleMenu: next.isShowingMenu.toggle()
    }
    return next
}
