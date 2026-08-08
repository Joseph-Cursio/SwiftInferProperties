import OrderedCollections

/// A seeded LCG. Deliberately not `SystemRandomNumberGenerator` and not
/// `Date`-derived: a counterexample here must be replayable from the seed alone,
/// and the repo's generator guidance treats unseeded sampling in a measurement
/// harness as a defect rather than a convenience. Same construction as
/// `fixtures/equatable-signal`'s driver, so the two fixtures' numbers are
/// produced the same way.
public struct SeededGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func nextRaw() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 16
    }

    public mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(nextRaw() % span)
    }
}

/// The three `OrderedSet<Int>` domains under comparison.
///
/// Each models the **reachable value set** of a generator expression, not its
/// `Gen` pipeline. The correspondence to the real expressions is asserted in
/// `README.md` §5 and pinned in the main suite by
/// `CuratedOCRecipeDomainTests`, so the two cannot drift silently.
public enum Domain: String, CaseIterable, Sendable {

    /// `Gen<Int>.int(in: 0 ... 100).map { OrderedSet([$0, $0+1, $0+2, $0+3]) }`
    ///
    /// The shipped recipe before 2026-08-08. **101 reachable values**, every one
    /// of them four consecutive ascending non-negative integers.
    case current

    /// `Gen<Int>.int(in: -100 ... 100).array(of: 1 ... 6).map { OrderedSet($0) }`
    ///
    /// The widened recipe. Arity varies, elements may be negative, and
    /// duplicates in the source array collapse on insert so the realised count
    /// can fall below the drawn one.
    ///
    /// **The floor is 1, not 0, and that is deliberate** — see `README.md` §4.
    /// These recipes serve `index(after:)` / `index(before:)` monotonicity
    /// picks, and an empty receiver has no valid index to advance from. The
    /// kit's `0 ... 8` is right for the Equatable/Hashable laws it serves and
    /// wrong here; the difference is purpose, not oversight.
    case widened

    /// `Gen<Int>.int(in: -100 ... 100).array(of: 0 ... 8).map { OrderedSet($0) }`
    ///
    /// `PropertyLawCollections.smallIntOrderedSet()`, the kit's own generator,
    /// carried as a reference arm so "did we reach parity" is measured rather
    /// than asserted. Admits the empty set, which `widened` excludes.
    case kit

    public func sample(_ generator: inout SeededGenerator) -> OrderedSet<Int> {
        switch self {
        case .current:
            let seed = generator.nextInt(in: 0 ... 100)
            return OrderedSet([seed, seed + 1, seed + 2, seed + 3])
        case .widened:
            let count = generator.nextInt(in: 1 ... 6)
            return OrderedSet((0 ..< count).map { _ in generator.nextInt(in: -100 ... 100) })
        case .kit:
            let count = generator.nextInt(in: 0 ... 8)
            return OrderedSet((0 ..< count).map { _ in generator.nextInt(in: -100 ... 100) })
        }
    }

    /// Every value `current` can reach, in order. Only 101 of them, which is why
    /// this fixture can make an **exhaustive** claim about that domain rather
    /// than a sampled one — the difference between "no counterexample exists"
    /// and "we did not find one in N trials".
    public static var currentDomainExhaustive: [OrderedSet<Int>] {
        (0 ... 100).map { OrderedSet([$0, $0 + 1, $0 + 2, $0 + 3]) }
    }
}
