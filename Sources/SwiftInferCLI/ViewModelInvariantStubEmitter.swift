import Foundation

/// PROTOTYPE — emits a verifier that checks a view-model's state invariant is
/// *maintained* by its actions: construct the view model, assert the predicate
/// on the initial state, then drive **randomized multi-step action sequences**
/// (a seeded PRNG picks a random action — and, for single-arg actions, a random
/// candidate value — at each step), re-asserting the predicate after every
/// application. A violation at any step → a counterexample sequence, greedily
/// **shrunk** to the smallest still-failing sequence → defaultFails; holding
/// across every sequence → bothPass.
///
/// **Why sequences, not a single pass.** The prior version applied each action
/// exactly once in sorted order — one fixed sequence — so it missed any bug
/// needing a different order, a repetition, or a subset (the classic
/// reset-then-empty interleaving). Randomized sequences explore those, matching
/// the reducer `ActionSequenceStubEmitter`'s posture (1024 sequences + a shrink
/// primitive). Deterministic: a fixed seed makes the exploration byte-stable, so
/// re-runs and the measured corpora reproduce exactly.
///
/// **Scope (this slice):** zero-arg-constructible view models over the
/// generatable action alphabet (no-arg + single-arg-over-candidates). Non-
/// generatable / multi-arg actions are skipped — disclosed in the header.
public enum ViewModelInvariantStubEmitter {

    /// One action to drive. `valuesExpression` is `nil` for a no-arg action;
    /// otherwise the `[T]` candidate expression.
    public struct Driver: Equatable, Sendable {
        public let name: String
        public let label: String?
        public let valuesExpression: String?

        public init(name: String, label: String?, valuesExpression: String?) {
            self.name = name
            self.label = label
            self.valuesExpression = valuesExpression
        }
    }

    public struct Inputs: Equatable, Sendable {
        public let typeName: String
        /// The invariant predicate over a `probe` instance
        /// (`ViewModelRefintResolver.Resolved.predicate`).
        public let predicate: String
        public let drivers: [Driver]
        /// Actions excluded from the drive (non-generatable / multi-arg) —
        /// disclosed in the emitted header for explainability.
        public let excludedActions: [String]

        public init(
            typeName: String,
            predicate: String,
            drivers: [Driver],
            excludedActions: [String] = []
        ) {
            self.typeName = typeName
            self.predicate = predicate
            self.drivers = drivers
            self.excludedActions = excludedActions
        }
    }

    /// Number of randomized sequences + the per-sequence step ceiling. Small
    /// enough to stay well inside the PRD §15 perf target, large enough to hit
    /// short interleavings with high probability.
    static let sequenceCount = 500
    static let maxSteps = 12

    public static func emit(_ inputs: Inputs) -> String {
        [headerBlock(inputs), seededRNG, typeHelpers(inputs), harnessBlock(inputs)]
            .joined(separator: "\n\n")
    }

    private static func headerBlock(_ inputs: Inputs) -> String {
        let excluded = inputs.excludedActions.isEmpty
            ? ""
            : "\n// Excluded (non-generatable / multi-arg): "
                + inputs.excludedActions.joined(separator: ", ")
        return """
        // PROTOTYPE — auto-generated ViewModel state-invariant verifier (randomized sequences).
        // Type: \(inputs.typeName)
        // Invariant (after every action): \(inputs.predicate)\(excluded)
        import Foundation
        """
    }

    /// Type-parameterized helpers: the action count, the invariant predicate,
    /// and the replayable per-step dispatch.
    private static func typeHelpers(_ inputs: Inputs) -> String {
        """
        let actionCount = \(inputs.drivers.count)

        func violates(_ probe: \(inputs.typeName)) -> Bool { !(\(inputs.predicate)) }

        func applyStep(_ probe: \(inputs.typeName), _ actionIndex: Int, _ argIndex: Int) {
            switch actionIndex {
        \(applyStepArms(inputs))
            default: break
            }
        }
        """
    }

    /// The exploration harness: replay-for-shrink, the seeded randomized search,
    /// greedy shrink, and the outcome markers.
    private static func harnessBlock(_ inputs: Inputs) -> String {
        """
        func replayFails(_ steps: [(Int, Int)]) -> Bool {
            let probe = \(inputs.typeName)()
            if violates(probe) { return true }
            for (actionIndex, argIndex) in steps {
                applyStep(probe, actionIndex, argIndex)
                if violates(probe) { return true }
            }
            return false
        }

        func findCounterexample() -> [(Int, Int)]? {
            var rng = SeededRNG(seed: 0xD1B54A32D192ED03)
            for _ in 0 ..< \(sequenceCount) {
                let probe = \(inputs.typeName)()
                if violates(probe) { return [] }
                if actionCount == 0 { break }
                var steps: [(Int, Int)] = []
                let length = Int.random(in: 1 ... \(maxSteps), using: &rng)
                for _ in 0 ..< length {
                    let action = Int.random(in: 0 ..< actionCount, using: &rng)
                    let arg = Int.random(in: 0 ..< 8, using: &rng)
                    steps.append((action, arg))
                    applyStep(probe, action, arg)
                    if violates(probe) { return steps }
                }
            }
            return nil
        }

        \(outcomeBlock)
        """
    }

    /// Greedy-shrink the counterexample and emit the outcome markers.
    private static let outcomeBlock = """
    if let failing = findCounterexample() {
        var minimal = failing
        var index = 0
        while index < minimal.count {
            var candidate = minimal
            candidate.remove(at: index)
            if replayFails(candidate) { minimal = candidate } else { index += 1 }
        }
        print("VERIFY_DEFAULT_RESULT: FAIL")
        print("VERIFY_DEFAULT_TRIAL: 0")
        print("VERIFY_DEFAULT_SHRUNK: \\(minimal.map { $0.0 })")
        exit(1)
    } else {
        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \(sequenceCount)")
        print("VERIFY_EDGE_RESULT: PASS")
        print("VERIFY_EDGE_TRIALS: 0")
        print("VERIFY_EDGE_SAMPLED: 0")
        exit(0)
    }
    """

    /// A seeded splitmix64-style PRNG — deterministic action/arg selection so
    /// the exploration (and the measured corpora) reproduce byte-for-byte.
    private static let seededRNG = """
    struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &+ 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }
    """

    /// One `case <i>:` arm per driver — a no-arg call, or a candidate-indexed
    /// single-arg call.
    private static func applyStepArms(_ inputs: Inputs) -> String {
        let arms = inputs.drivers.enumerated().map { index, driver -> String in
            guard let values = driver.valuesExpression else {
                return "        case \(index): probe.\(driver.name)()"
            }
            let element = "values[argIndex % values.count]"
            let call = driver.label.map { "probe.\(driver.name)(\($0): \(element))" }
                ?? "probe.\(driver.name)(\(element))"
            return "        case \(index): let values = \(values); \(call)"
        }
        return arms.joined(separator: "\n")
    }
}
