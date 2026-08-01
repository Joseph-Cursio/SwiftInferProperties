import Foundation

/// The two implementations, plus the mutants.
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

    // MARK: - Mutants

    /// Every deliberate defect, so the test matrix can iterate them by name.
    ///
    /// `nonStrictComparator` and `disjunctiveComparator` are **comparator** mutants —
    /// the implementation is the correct built-in and the defect is in the ordering
    /// relation. They are separated because they fail differently: one traps, and the
    /// tests must expect that rather than a wrong answer.
    public enum Mutant: String, CaseIterable, Sendable {
        case dropsLastWhenOddCount
        case duplicatesFirst
        case ascendingInsteadOfDescending
        case unstableTieHandling
        case sortsByNameNotScore
        case returnsInputUnchanged
        case leavesLastElementUnsorted

        /// The mutated sort. Comparator mutants are not here — see `Comparators`.
        public func apply(
            _ input: [PlayerScore],
            by areInIncreasingOrder: (PlayerScore, PlayerScore) -> Bool
        ) -> [PlayerScore] {
            switch self {
            case .dropsLastWhenOddCount:
                let sorted = Sorts.builtinSorted(input, by: areInIncreasingOrder)
                return sorted.count % 2 == 1 ? Array(sorted.dropLast()) : sorted

            case .duplicatesFirst:
                let sorted = Sorts.builtinSorted(input, by: areInIncreasingOrder)
                guard let first = sorted.first else { return sorted }
                return [first] + sorted

            case .ascendingInsteadOfDescending:
                return Sorts.builtinSorted(input, by: { areInIncreasingOrder($1, $0) })

            case .unstableTieHandling:
                // Correct under a TOTAL order; differs from the stable built-in only
                // where the comparator leaves ties — i.e. arm A only.
                return Sorts.selectionSorted(input, by: areInIncreasingOrder)

            case .sortsByNameNotScore:
                return input.sorted { $0.name < $1.name }

            case .returnsInputUnchanged:
                return input

            case .leavesLastElementUnsorted:
                let sorted = Sorts.builtinSorted(input, by: areInIncreasingOrder)
                guard sorted.count > 1 else { return sorted }
                return Array(sorted.dropLast()) + [input[input.count - 1]]
            }
        }
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
