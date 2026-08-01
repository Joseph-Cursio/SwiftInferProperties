import Foundation
@testable import LeaderboardSort

/// **Test apparatus, and it lives in the TEST target on purpose.**
///
/// The first version of this fixture put the mutants, the law implementations and the
/// generators in `Sources/` — the directory `discover` was then pointed at. 6 of 13
/// suggestions in the resulting run were totality laws about the fixture's own law helpers,
/// and the README read that as "the tool cannot tell a subject from an apparatus".
///
/// That was unfair: the apparatus had been put in the product. A corpus you assembled and
/// then scan is not a measurement of the tool, and the first scorecard was withdrawn for
/// exactly this.
extension Sorts {

// MARK: - Mutants

/// Every deliberate defect, so the test matrix can iterate them by name.
///
/// `nonStrictComparator` and `disjunctiveComparator` are **comparator** mutants —
/// the implementation is the correct built-in and the defect is in the ordering
/// relation. They are separated because they fail differently: one traps, and the
/// tests must expect that rather than a wrong answer.
enum Mutant: String, CaseIterable, Sendable {
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
