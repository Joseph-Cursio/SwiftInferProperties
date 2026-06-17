// Verify-ready Mobius (Spotify) corpus — the `(Model, Event) -> Next<Model,
// Effect>` update shape (the `.mobius` carrier). Co-compiled into the verifier
// target (direct source inclusion) with MobiusCore declared as a package
// dependency, so `import MobiusCore` + `Next` resolve. Verified by extracting
// the new model from `Next.model` (nil = `.noChange`) and discarding effects.
//
// Unlabeled `_` params so the verifier's positional call compiles. CaseIterable
// Event for the action generator; Equatable, zero-arg Model for the loop's
// `var state = Model()`.
//
// Two idempotence witnesses:
//   - `reset` — returns the zero model → applying twice == once → bothPass.
//   - `refresh` — an exact-witness NAME whose body actually increments → NOT
//     idempotent → measured-defaultFails. The deliberate false positive proving
//     execution catches a name-based smell through the Mobius Next path (the
//     Mobius analogue of the idempotence corpus's `setBadge`).

import MobiusCore

public struct CounterModel: Equatable, Sendable {
    public var count: Int
    public init(count: Int = 0) {
        self.count = count
    }
}

public enum CounterEvent: CaseIterable, Sendable {
    case increment
    case reset
    case refresh
}

public enum CounterEffect: Sendable {}

public func counterUpdate(
    _ model: CounterModel,
    _ event: CounterEvent
) -> Next<CounterModel, CounterEffect> {
    switch event {
    case .increment: return .next(CounterModel(count: model.count + 1))
    case .reset:     return .next(CounterModel(count: 0))
    case .refresh:   return .next(CounterModel(count: model.count + 1)) // false positive
    }
}
