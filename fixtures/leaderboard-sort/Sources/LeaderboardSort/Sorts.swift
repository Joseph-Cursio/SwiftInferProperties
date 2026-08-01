import Foundation

/// The two implementations under test.
///
/// The MUTANTS used to live here and now live in the test target (`Mutants.swift`) — they
/// are apparatus, and putting apparatus in the scanned target is what made the first
/// scorecard noise.
///
/// ## Why selection sort, and not insertion sort
///
/// The differential law `mine(xs) == builtin(xs)` is only refutable if the two can
/// actually disagree. Swift's `sorted(by:)` is documented as **not guaranteed stable** —
/// but since Swift 5 it is a modified timsort that *is* stable in practice. So pairing it
/// with a hand-rolled **insertion** sort (also stable) gives two implementations that
/// agree on every input, and a law that cannot fail.
///
/// **Selection sort is naturally unstable.** Pairing that with the built-in makes the
/// disagreement real rather than theoretical — on arm A, and only on ties.
///
/// This is the fixture's first lesson and it is about the EXPERIMENT, not the code: a
/// differential law between two implementations chosen for convenience is usually
/// unfalsifiable, and reads exactly like a passing one.
public enum Sorts {

    /// Hand-rolled selection sort. Correct, and **unstable**: it swaps the selected
    /// element into position, which reorders equal elements it jumps over.
    public static func selectionSorted(
        _ input: [PlayerScore],
        by areInIncreasingOrder: (PlayerScore, PlayerScore) -> Bool
    ) -> [PlayerScore] {
        var items = input
        guard items.count > 1 else { return items }
        for start in 0..<(items.count - 1) {
            var best = start
            for candidate in (start + 1)..<items.count
            where areInIncreasingOrder(items[candidate], items[best]) {
                best = candidate
            }
            if best != start { items.swapAt(start, best) }
        }
        return items
    }

    /// The standard-library implementation, same comparator.
    public static func builtinSorted(
        _ input: [PlayerScore],
        by areInIncreasingOrder: (PlayerScore, PlayerScore) -> Bool
    ) -> [PlayerScore] {
        input.sorted(by: areInIncreasingOrder)
    }
}

// MARK: - The free-function control

/// The **control arm**: the same law, stated over a free function rather than a member.
///
/// It exists because that distinction is the most reliable way to make the tool go silent
/// for structural rather than semantic reasons — `homomorphism` measured **zero rows
/// across eight corpora and ~55,000 functions** because its gate wanted a free function
/// `[T] -> Int` and Swift writes `var count: Int`. Whatever `discover` says about
/// `Leaderboard.sorted`, it should be compared against what it says here.
public func sortedByScore(_ scores: [PlayerScore]) -> [PlayerScore] {
    scores.sorted(by: Comparators.byScoreDescending)
}

/// Free-function control for arm B.
public func sortedByScoreThenName(_ scores: [PlayerScore]) -> [PlayerScore] {
    scores.sorted(by: Comparators.byScoreThenName)
}
