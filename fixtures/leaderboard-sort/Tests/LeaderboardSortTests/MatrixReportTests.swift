import Testing
@testable import LeaderboardSort

/// **The mutant × law matrix, asserted rather than described.**
///
/// The README carries this table. It is generated here so the table cannot drift from the
/// code: every cell is an assertion, and `printableMatrix` renders the same data in the
/// README's shape for copying.
///
/// A cell is `kills` when some generated board refutes that law for that mutant.
@Suite("The matrix — every cell asserted")
struct MatrixReportTests {

    private static let trials = 200
    private static let players = 5
    private static let seed: UInt64 = 0xB0_1234

    private static var boards: [[PlayerScore]] {
        var generator = Generators(seed: seed)
        return (0..<trials).map { _ in generator.realisticBoard(playerCount: players) }
    }

    /// The four laws under test, in README column order.
    enum Law: String, CaseIterable {
        case idempotence
        case ordering
        case permutation
        case oracle   // agrees with the reference implementation

        func holds(_ mutant: Sorts.Mutant, _ board: [PlayerScore]) -> Bool {
            let less = Comparators.byScoreThenName
            let sort: Laws.Sort = { input, comparator in mutant.apply(input, by: comparator) }
            switch self {
            case .idempotence: return Laws.idempotence(sort, board, less)
            case .ordering: return Laws.isOrdered(sort, board, less)
            case .permutation: return Laws.isPermutation(sort, board, less)
            case .oracle: return mutant.apply(board, by: less) == Sorts.builtinSorted(board, by: less)
            }
        }
    }

    static func kills(_ law: Law, _ mutant: Sorts.Mutant) -> Bool {
        boards.contains { !law.holds(mutant, $0) }
    }

    /// **The measured matrix.** Each row: mutant, then whether each law rejects it.
    ///
    /// Written out rather than computed-and-compared so a change shows up as a diff on a
    /// literal, which is reviewable. `matrixIsAsMeasured` is what keeps it true.
    static let expected: [Sorts.Mutant: [Law: Bool]] = [
        .dropsLastWhenOddCount: [.idempotence: false, .ordering: false, .permutation: true, .oracle: true],
        .duplicatesFirst: [.idempotence: true, .ordering: false, .permutation: true, .oracle: true],
        .ascendingInsteadOfDescending: [.idempotence: false, .ordering: true, .permutation: false, .oracle: true],
        .unstableTieHandling: [.idempotence: false, .ordering: false, .permutation: false, .oracle: false],
        .sortsByNameNotScore: [.idempotence: false, .ordering: true, .permutation: false, .oracle: true],
        .returnsInputUnchanged: [.idempotence: false, .ordering: true, .permutation: false, .oracle: true],
        .leavesLastElementUnsorted: [.idempotence: true, .ordering: true, .permutation: true, .oracle: true]
    ]

    @Test("every cell matches what the code actually does")
    func matrixIsAsMeasured() {
        for mutant in Sorts.Mutant.allCases {
            guard let row = Self.expected[mutant] else {
                Issue.record("no expected row for \(mutant.rawValue)")
                continue
            }
            for law in Law.allCases {
                #expect(
                    Self.kills(law, mutant) == row[law],
                    Comment(rawValue: "\(mutant.rawValue) × \(law.rawValue): "
                        + "measured \(Self.kills(law, mutant)), table says \(row[law] ?? false)")
                )
            }
        }
    }

    /// **The headline the table exists to show: ordering and permutation are complements.**
    ///
    /// Each catches mutants the other passes, so a suite carrying one of them reports green
    /// on defects the other would have caught.
    @Test("neither ordering nor permutation subsumes the other")
    func orderingAndPermutationAreComplements() {
        let orderingMisses = Sorts.Mutant.allCases.filter {
            Self.expected[$0]?[.permutation] == true && Self.expected[$0]?[.ordering] == false
        }
        let permutationMisses = Sorts.Mutant.allCases.filter {
            Self.expected[$0]?[.ordering] == true && Self.expected[$0]?[.permutation] == false
        }
        #expect(!orderingMisses.isEmpty, "permutation must catch something ordering does not")
        #expect(!permutationMisses.isEmpty, "and vice versa")
    }

    /// Idempotence is the weak one: it rejects fewer mutants than either of the others.
    @Test("idempotence is the weakest of the four")
    func idempotenceIsWeakest() {
        func killCount(_ law: Law) -> Int {
            Sorts.Mutant.allCases.filter { Self.expected[$0]?[law] == true }.count
        }
        #expect(killCount(.idempotence) < killCount(.ordering))
        #expect(killCount(.idempotence) < killCount(.permutation))

        // **The oracle catches 6 of 7, and the seventh is the interesting one.**
        // `unstableTieHandling` passes ALL FOUR laws under arm B — correctly, because a
        // total order leaves no ties to mishandle, so under this comparator it is not a
        // defect at all. The same mutant is refuted immediately under arm A
        // (`differentialFailsOnTies`). An all-passes row is the two arms made concrete:
        // whether something IS a bug depends on the comparator, not on the sort.
        #expect(killCount(.oracle) == Sorts.Mutant.allCases.count - 1)
        let survivesEverything = Sorts.Mutant.allCases.filter { mutant in
            Law.allCases.allSatisfy { Self.expected[mutant]?[$0] == false }
        }
        #expect(survivesEverything == [.unstableTieHandling])
    }

    /// The README's table, rendered from the same data.
    static var printableMatrix: String {
        var lines = ["| mutant | idempotence | ordering | permutation | oracle |", "|---|---|---|---|---|"]
        for mutant in Sorts.Mutant.allCases {
            let cells = Law.allCases.map { expected[mutant]?[$0] == true ? "**kills**" : "passes" }
            lines.append("| `\(mutant.rawValue)` | \(cells.joined(separator: " | ")) |")
        }
        return lines.joined(separator: "\n")
    }

    @Test("the printable table covers every mutant")
    func printableTableIsComplete() {
        let table = Self.printableMatrix
        for mutant in Sorts.Mutant.allCases {
            #expect(table.contains(mutant.rawValue))
        }
        print(table)
    }
}
