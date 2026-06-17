// ReSwift-style **free-function** reducer — the `(Action, State?) -> State`
// shape: Action FIRST, Optional incoming State, non-optional returned State
// (ReSwift's `Reducer` typealias). Recognized as the `.reSwift` carrier and,
// once per-framework verify emit landed, verified by emitting the canonical
// state-returning call with REVERSED args (`reducer(action, state)`).
//
// Witness: `reset` (exact-match idempotence vocabulary — returns the zero
// state, so applying it twice equals applying it once → measured-bothPass,
// proving the reversed-arg emit compiles + runs correctly). `increment` is a
// non-witness driver. State is Equatable + zero-arg constructible (the loop's
// `var state = State()` requirement); Action is CaseIterable for the
// generator.

public struct ReSwiftCounterState: Equatable, Sendable {
    public var value: Int
    public init(value: Int = 0) {
        self.value = value
    }
}

public enum ReSwiftCounterAction: CaseIterable, Sendable {
    case increment
    case reset
}

// Unlabeled `_` params, matching ReSwift's `Reducer` typealias
// `(_ action: Action, _ state: State?) -> State` — the verifier calls it
// positionally, like every other corpus reducer.
public func reSwiftCounterReducer(
    _ action: ReSwiftCounterAction,
    _ state: ReSwiftCounterState?
) -> ReSwiftCounterState {
    let current = state ?? ReSwiftCounterState()
    switch action {
    case .increment: return ReSwiftCounterState(value: current.value + 1)
    case .reset: return ReSwiftCounterState(value: 0)
    }
}
