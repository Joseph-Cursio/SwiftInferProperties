// Verify-ready value-semantics corpus — NEGATIVE control (closure capture).
//
// `ClosureCounter` stores a closure that captures a heap `var box`; every value
// copy shares the same closure and thus the same box (pbt-book Ch. 9 §9.1.3 /
// Example 3). The leak is subtle: mutating a *copy* doesn't change the
// original's observable `lastValue` immediately — it only surfaces on the
// original's NEXT `tick()`, which sees the contaminated box. The single-step
// law passes; the multi-step interleaving law (kit v3.5.0) catches it, so the
// harness reports `measured-defaultFails`.

public struct ClosureCounter: Equatable, @unchecked Sendable {

    private let increment: () -> Int
    public private(set) var lastValue: Int = 0

    public init() {
        var box = 0
        increment = { box += 1; return box }
    }

    public static func == (lhs: ClosureCounter, rhs: ClosureCounter) -> Bool {
        lhs.lastValue == rhs.lastValue
    }

    public mutating func tick() {
        lastValue = increment()
    }
}
