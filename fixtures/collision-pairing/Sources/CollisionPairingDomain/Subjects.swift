import Foundation

/// A deterministic generator, so a scorecard is re-derivable rather than flaky.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// How the second operand is drawn. Mirrors `SwiftInferCore.OperandPairing`; kept as its
/// own type because this fixture is a standalone package and must not depend on the tool
/// it is scoring.
public enum Pairing: String, CaseIterable, Sendable {
    case independent
    case identical
    case permuted
    case overlapping
}

/// The subject family: a keyed merge. **Non-commutativity lives entirely in the
/// tie-break**, which only runs when the two operands share a key.
public enum Merge {

    /// The correct implementation for this fixture's purposes: commutative, because
    /// colliding keys resolve to the larger value regardless of argument order.
    public static func correct(_ lhs: [Int: Int], _ rhs: [Int: Int]) -> [Int: Int] {
        lhs.merging(rhs) { Swift.max($0, $1) }
    }

    /// **Mutant 1 — last-write-wins.** Commutative on disjoint keys, not on shared ones.
    public static func lastWriteWins(_ lhs: [Int: Int], _ rhs: [Int: Int]) -> [Int: Int] {
        lhs.merging(rhs) { _, new in new }
    }

    /// **Mutant 2 — first-write-wins.** The mirror of mutant 1.
    public static func firstWriteWins(_ lhs: [Int: Int], _ rhs: [Int: Int]) -> [Int: Int] {
        lhs.merging(rhs) { old, _ in old }
    }

    /// **Mutant 3 — min instead of max.** Still commutative; a control that must NOT be
    /// killed by any pairing, because a scorer that kills everything is measuring
    /// nothing.
    public static func minOnCollision(_ lhs: [Int: Int], _ rhs: [Int: Int]) -> [Int: Int] {
        lhs.merging(rhs) { Swift.min($0, $1) }
    }

    /// **Mutant 4 — drops the left operand's exclusive keys.** Fails on ordinary
    /// distinct operands, so INDEPENDENT draws catch it. Present so the scorecard can
    /// show that paired draws are additive rather than better.
    public static func dropsLeftOnly(_ lhs: [Int: Int], _ rhs: [Int: Int]) -> [Int: Int] {
        var result = rhs
        for (key, value) in lhs where rhs[key] != nil { result[key] = Swift.max(value, rhs[key]!) }
        return result
    }
}

public struct LawOutcome: Sendable {
    public let passed: Bool
    public let trialsRun: Int
    public let counterexample: String?
    public init(trialsRun: Int, counterexample: String? = nil) {
        self.trialsRun = trialsRun
        self.counterexample = counterexample
        passed = counterexample == nil
    }
}

/// The key space operands are drawn from. **The axis that decides whether a trial
/// budget can substitute for pairing.**
public enum KeySpace: String, CaseIterable, Sendable {
    /// Ten thousand keys. Collision is rare per trial but not negligible in aggregate,
    /// so a large enough budget finds it.
    case narrow
    /// A billion keys — the analogue of `CommutativityStubEmitter`'s actual default,
    /// which draws `Complex<Double>` from ±1,000,000. Collision is effectively
    /// impossible at any budget the tool could run.
    case wide

    public var upperBound: Int {
        switch self {
        case .narrow: 10_000
        case .wide: 1_000_000_000
        }
    }
}

/// Checks `f(a, b) == f(b, a)` under a given pairing and key space.
public func checkCommutativity(
    _ subject: @Sendable ([Int: Int], [Int: Int]) -> [Int: Int],
    pairing: Pairing,
    keySpace: KeySpace = .narrow,
    trials: Int = 20_000,
    seed: UInt64 = 0x5EED_1234
) -> LawOutcome {
    var generator = SeededGenerator(seed: seed)

    func draw(_ rng: inout SeededGenerator) -> [Int: Int] {
        let count = Int.random(in: 1 ... 4, using: &rng)
        var dictionary: [Int: Int] = [:]
        for _ in 0 ..< count {
            dictionary[Int.random(in: 0 ..< keySpace.upperBound, using: &rng)] = Int.random(in: 0 ..< 100, using: &rng)
        }
        return dictionary
    }

    for trial in 1 ... trials {
        let lhs = draw(&generator)
        let rhs: [Int: Int]
        switch pairing {
        case .independent:
            rhs = draw(&generator)

        case .identical:
            rhs = lhs

        case .permuted:
            // Same keys, values reassigned among them: the key set collides exactly.
            let keys = Array(lhs.keys)
            let values = Array(lhs.values).shuffled(using: &generator)
            rhs = Dictionary(uniqueKeysWithValues: zip(keys, values))

        case .overlapping:
            // Share one key, differ elsewhere — the tie-break runs and the operands
            // stay distinct.
            var derived = draw(&generator)
            if let shared = lhs.keys.first {
                derived[shared] = Int.random(in: 0 ..< 100, using: &generator)
            }
            rhs = derived
        }

        if subject(lhs, rhs) != subject(rhs, lhs) {
            return LawOutcome(trialsRun: trial, counterexample: "\(lhs) vs \(rhs)")
        }
    }
    return LawOutcome(trialsRun: trials)
}
