// Cycle 116 — verify-ready idempotence survey corpus, widening fixture.
//
// Elm-style **free-function** reducer (top-level `func`, the `.elmStyle`
// carrier — M1.C.1) rather than a struct static method. Widens the corpus's
// carrier coverage: the cycle-115 reducers are all `.generic` struct
// methods. Witness: `refresh` (resets to the zero state → idempotent).
// `increment` and `toggleMenu` are non-witness drivers (`toggle*` is
// deliberately excluded from the witness vocabulary — toggling twice
// returns to the original state, not idempotent).
//
// **Named uniquely (`reduceElmCounter`, not `reduce`) on purpose.** A free
// function whose name collides with the struct methods' `reduce` can't be
// pin-resolved: `verify-interaction`'s `ReducerPin` for a bare name
// (no type prefix) matches *every* same-named reducer, so a free `reduce`
// alongside `Foo.reduce` is ambiguous. That pin-grammar gap (free-function
// disambiguation) is a cycle-116 finding / follow-up; a unique name keeps
// the corpus surveyable today.

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

public func reduceElmCounter(_ state: ElmCounterState, _ action: ElmCounterAction) -> ElmCounterState {
    switch action {
    case .increment: return ElmCounterState(value: state.value + 1, menuOpen: state.menuOpen)
    case .refresh: return ElmCounterState(value: 0, menuOpen: false)
    case .toggleMenu: return ElmCounterState(value: state.value, menuOpen: !state.menuOpen)
    }
}
