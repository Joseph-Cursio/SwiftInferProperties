import OrderedCollections

/// Subjects for the single-value law `total(set) == set.reduce(0, +)`.
///
/// Each mutant is wrong in a way that is invisible to a *specific* narrowness of
/// the `current` domain, which is the point: a mutant nobody's generator can
/// reach is the measurable form of "this generator is too narrow". They are not
/// arbitrary — each names one property `current` holds for **every** value it
/// can produce.
public enum Subject: String, CaseIterable, Sendable {

    /// The reference implementation.
    case correct

    /// Assumes the elements are an ascending run with step 1, and uses the
    /// arithmetic-series shortcut. `current` produces `{n, n+1, n+2, n+3}` and
    /// **nothing else**, so this mutant is correct over that entire domain —
    /// exhaustively, not probably.
    case arithmeticSeriesShortcut

    /// Sums only the first four elements. `current` always has exactly four, so
    /// the truncation never shows.
    case fixedArityFour

    /// Clamps each element at zero. `current` draws from `0 ... 100`, so no
    /// element is ever negative and the clamp is never exercised.
    case nonNegativeAssumption

    public func total(_ set: OrderedSet<Int>) -> Int {
        switch self {
        case .correct:
            return set.reduce(0, +)
        case .arithmeticSeriesShortcut:
            guard let first = set.first else { return 0 }
            let count = set.count
            return first * count + (count * (count - 1)) / 2
        case .fixedArityFour:
            return set.prefix(4).reduce(0, +)
        case .nonNegativeAssumption:
            return set.reduce(0) { $0 + max(0, $1) }
        }
    }
}

/// A wrapper whose `==` **drops iteration order** — the `OrderedSet` order
/// projection named in `fixtures/equatable-signal` as one of three real
/// projection bugs. Kept here to measure what the domain change does NOT reach.
public struct OrderBlindOrderedSet: Equatable, Sendable {
    public let storage: OrderedSet<Int>

    public init(_ storage: OrderedSet<Int>) {
        self.storage = storage
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        Set(lhs.storage) == Set(rhs.storage)
    }
}

// MARK: - Outcomes

public struct LawOutcome: Sendable {
    public var trialsRun: Int
    public var counterexample: String?

    public var passed: Bool { counterexample == nil }

    public init(trialsRun: Int, counterexample: String? = nil) {
        self.trialsRun = trialsRun
        self.counterexample = counterexample
    }
}

// MARK: - Drivers

/// Runs `subject.total(x) == x.reduce(0, +)` over sampled values from `domain`,
/// stopping at the first divergence.
public func checkTotalLaw(
    subject: Subject,
    domain: Domain,
    trials: Int = 2_000,
    seed: UInt64 = 0x5EED_1234
) -> LawOutcome {
    var generator = SeededGenerator(seed: seed)
    for trial in 1 ... trials {
        let value = domain.sample(&generator)
        if subject.total(value) != value.reduce(0, +) {
            return LawOutcome(
                trialsRun: trial,
                counterexample: "\(Array(value)) → \(subject.total(value)), expected \(value.reduce(0, +))"
            )
        }
    }
    return LawOutcome(trialsRun: trials)
}

/// The same law over **every value `current` can reach** — all 101 of them.
///
/// This is the arm that makes the finding a proof rather than a sampling
/// result: a mutant that survives here is not merely unlikely to be caught, it
/// is *unreachable* by that domain.
public func checkTotalLawExhaustivelyOverCurrentDomain(subject: Subject) -> LawOutcome {
    let values = Domain.currentDomainExhaustive
    for (index, value) in values.enumerated() where subject.total(value) != value.reduce(0, +) {
        return LawOutcome(
            trialsRun: index + 1,
            counterexample: "\(Array(value)) → \(subject.total(value)), expected \(value.reduce(0, +))"
        )
    }
    return LawOutcome(trialsRun: values.count)
}

/// How a pair of values is drawn for the order-projection law.
public enum Pairing: String, CaseIterable, Sendable {
    /// Two independent draws — what every generator in `Domain` actually does.
    case independent
    /// One draw, and a rotation of it: same elements, different order. Not a
    /// generator this repo emits; carried to show what WOULD catch the bug.
    case permuted
}

/// Runs `(a == b) == a.elementsEqual(b)` — the sequence-view model law this repo
/// emits — against the order-blind wrapper.
public func checkOrderProjectionLaw(
    domain: Domain,
    pairing: Pairing,
    trials: Int = 20_000,
    seed: UInt64 = 0x5EED_1234
) -> LawOutcome {
    var generator = SeededGenerator(seed: seed)
    for trial in 1 ... trials {
        let left = domain.sample(&generator)
        let right: OrderedSet<Int>
        switch pairing {
        case .independent:
            right = domain.sample(&generator)
        case .permuted:
            var rotated = Array(left)
            if rotated.count > 1 { rotated.append(rotated.removeFirst()) }
            right = OrderedSet(rotated)
        }
        let byOperator = OrderBlindOrderedSet(left) == OrderBlindOrderedSet(right)
        let byModel = left.elementsEqual(right)
        if byOperator != byModel {
            return LawOutcome(
                trialsRun: trial,
                counterexample: "\(Array(left)) vs \(Array(right)): == → \(byOperator), elementsEqual → \(byModel)"
            )
        }
    }
    return LawOutcome(trialsRun: trials)
}
