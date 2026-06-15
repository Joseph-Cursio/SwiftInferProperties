// Cycle 116 — verify-ready idempotence survey corpus, widening fixture.
//
// Elm-style **free-function** reducer (top-level `func reduce(_:_:)`, the
// `.elmStyle` carrier — M1.C.1) rather than a struct static method. Widens
// the corpus's carrier coverage: the cycle-115 reducers are all `.generic`
// struct methods. Witness: `refresh` (resets to the zero state →
// idempotent). `increment` and `toggleMenu` are non-witness drivers
// (`toggle*` is deliberately excluded from the witness vocabulary —
// toggling twice returns to the original state, not idempotent).
//
// **Named `reduce`** (the Hand06 / Elm idiom) on purpose: a free function
// whose name collides with the struct methods' `reduce` was unresolvable
// until cycle 117 taught pin resolution to prefer an exact qualified-name
// match (a free function's qualifiedName is its bare name `reduce`, which
// now disambiguates it from `Foo.reduce`). This fixture is the regression
// guard for that fix — the cycle-116 workaround (`reduceElmCounter`) is no
// longer needed.

public struct ElmCounterState: Equatable, Sendable {
    public var value: Int
    public var menuOpen: Bool
    public init(value: Int = 0, menuOpen: Bool = false) {
        self.value = value
        self.menuOpen = menuOpen
    }
}

public enum ElmCounterAction: CaseIterable, Sendable {
    case increment
    case refresh
    case toggleMenu
}

public func reduce(_ state: ElmCounterState, _ action: ElmCounterAction) -> ElmCounterState {
    switch action {
    case .increment: return ElmCounterState(value: state.value + 1, menuOpen: state.menuOpen)
    case .refresh: return ElmCounterState(value: 0, menuOpen: false)
    case .toggleMenu: return ElmCounterState(value: state.value, menuOpen: !state.menuOpen)
    }
}
