// Phase 2 (Redux) — determinism verify corpus, fixture 2 of 2.
//
// The deliberate false positive — and the whole point of runtime
// determinism verification. This reducer stamps every result with a
// random `tag`, so applying the same (state, action) twice yields
// DIFFERENT results: determinism is violated. Yet the static purity
// analyzer (`ReducerPurityAnalyzer`) only rules out TCA effects, Task, and
// hidden mutation — it does NOT inspect for `Int.random` / `Date()` /
// `UUID()` — so it labels this reducer `.pure`.
//
// Static analysis therefore cannot catch this; the measured determinism
// check does → `measured-defaultFails`, suppressed (never promoted). A
// reducer that reads a random source really isn't deterministic, so this
// is a true negative, not a tool false positive.

public struct NondeterministicTagReducer {
    public struct State: Equatable, Sendable {
        public var value: Int
        public var tag: Int
        public init(value: Int = 0, tag: Int = 0) {
            self.value = value
            self.tag = tag
        }
    }

    public enum Action: CaseIterable, Sendable {
        case bump
        case halve
    }

    public static func reduce(_ state: State, _ action: Action) -> State {
        var next = state
        switch action {
        case .bump:
            next.value += 1
        case .halve:
            next.value /= 2
        }
        // Nondeterministic — the source of the violation. Invisible to
        // static purity analysis; caught at runtime by `reduce(s, a) ==
        // reduce(s, a)` failing.
        next.tag = Int.random(in: Int.min ... Int.max)
        return next
    }
}
