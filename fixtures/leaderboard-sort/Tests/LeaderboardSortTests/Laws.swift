import Foundation
@testable import LeaderboardSort

/// The candidate laws, each stated so it can REJECT an implementation.
///
/// Named and separated because the fixture's output is a **mutant × law matrix**: which
/// laws kill which defects. A law that no mutant fails is not evidence the code is right,
/// it is evidence the law is weak — which is the `f(x) == f(x)` failure mode stated
/// positively.
public enum Laws {

    public typealias Sort = ([PlayerScore], (PlayerScore, PlayerScore) -> Bool) -> [PlayerScore]

    /// Sorting twice equals sorting once. The catalog proves this on `Array`
    /// (`a.sorted().sorted() == a.sorted()`, tagged `idempotence` 2026-08-01).
    public static func idempotence(
        _ sort: Sort,
        _ input: [PlayerScore],
        _ less: @escaping (PlayerScore, PlayerScore) -> Bool
    ) -> Bool {
        let once = sort(input, less)
        return sort(once, less) == once
    }

    /// The output is a PERMUTATION of the input — multiset equality.
    ///
    /// This is the law that catches a sort dropping or duplicating an element, and
    /// neither the ordering law nor idempotence sees those. The catalog's `partition`
    /// template is one of five still measuring **zero rows**, and this shape is why that
    /// matters: it is the strongest law here and the one most likely to go unproposed.
    public static func isPermutation(
        _ sort: Sort,
        _ input: [PlayerScore],
        _ less: @escaping (PlayerScore, PlayerScore) -> Bool
    ) -> Bool {
        let output = sort(input, less)
        guard output.count == input.count else { return false }
        return multiset(output) == multiset(input)
    }

    /// Adjacent pairs respect the comparator — the ordering claim itself.
    public static func isOrdered(
        _ sort: Sort,
        _ input: [PlayerScore],
        _ less: @escaping (PlayerScore, PlayerScore) -> Bool
    ) -> Bool {
        let output = sort(input, less)
        guard output.count > 1 else { return true }
        for index in 0..<(output.count - 1) where less(output[index + 1], output[index]) {
            return false
        }
        return true
    }

    /// The two implementations agree, elementwise.
    ///
    /// TRUE on arm B (total order). FALSE on arm A whenever the input contains a tie —
    /// which is the whole reason the hand-rolled arm is a selection sort.
    public static func differential(
        _ input: [PlayerScore],
        _ less: @escaping (PlayerScore, PlayerScore) -> Bool
    ) -> Bool {
        Sorts.selectionSorted(input, by: less) == Sorts.builtinSorted(input, by: less)
    }

    /// The **model law** — the differential stated through the score projection.
    ///
    /// Holds on arm A even where `differential` fails, because the disagreement is
    /// entirely within tie groups and the projection collapses them. This is
    /// `fixtures/equatable-signal`'s recorded recommendation made concrete: *propose the
    /// model law, not the equality laws, for projections.*
    public static func differentialUnderScoreProjection(
        _ input: [PlayerScore],
        _ less: @escaping (PlayerScore, PlayerScore) -> Bool
    ) -> Bool {
        Sorts.selectionSorted(input, by: less).map(\.score)
            == Sorts.builtinSorted(input, by: less).map(\.score)
    }

    /// A strict weak ordering: irreflexive and asymmetric, checked pointwise.
    ///
    /// Transitivity needs three values and is checked separately by the caller, because a
    /// pointwise check that silently omits it is the kind of half-law that reads as a
    /// full one.
    public static func isStrictWeakOrdering(
        _ less: (PlayerScore, PlayerScore) -> Bool,
        over sample: [PlayerScore]
    ) -> Bool {
        for value in sample where less(value, value) { return false }        // irreflexive
        for lhs in sample {
            for rhs in sample where less(lhs, rhs) && less(rhs, lhs) {       // asymmetric
                return false
            }
        }
        for lhs in sample {
            for mid in sample where less(lhs, mid) {
                for rhs in sample where less(mid, rhs) && !less(lhs, rhs) {  // transitive
                    return false
                }
            }
        }
        return true
    }

    private static func multiset(_ values: [PlayerScore]) -> [PlayerScore: Int] {
        var counts: [PlayerScore: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        return counts
    }
}
