import Testing
@testable import LeaderboardSort

/// **The fixture's answer: which laws reject which defects.**
///
/// The point is not that the correct implementation passes — it is which laws a *wrong*
/// one survives. A law no mutant fails is a weak law, not a clean bill of health.
@Suite("Sort walkthrough — the mutant × law matrix")
struct MutantMatrixTests {

    private static let trials = 200
    private static let players = 5

    private static func boards(seed: UInt64) -> [[PlayerScore]] {
        var generator = Generators(seed: seed)
        return (0..<trials).map { _ in generator.realisticBoard(playerCount: players) }
    }

    /// A law "kills" a mutant when some generated board refutes it.
    private static func kills(
        law: (Sorts.Mutant, [PlayerScore]) -> Bool,
        _ mutant: Sorts.Mutant,
        seed: UInt64 = 0xB0_1234
    ) -> Bool {
        boards(seed: seed).contains { !law(mutant, $0) }
    }

    // MARK: - Arm B (total order) — the four laws against every mutant

    @Test("permutation is the only law that catches element loss and duplication")
    func permutationCatchesWhatOrderingCannot() {
        let less = Comparators.byScoreThenName

        for mutant in [Sorts.Mutant.dropsLastWhenOddCount, .duplicatesFirst] {
            #expect(
                Self.kills(law: { m, b in Laws.isPermutation({ m.apply($0, by: $1) }, b, less) }, mutant),
                "permutation must reject \(mutant.rawValue)"
            )
            // ...and the ordering law does NOT. A shorter sorted list is still sorted;
            // a duplicated head is still in order.
            #expect(
                !Self.kills(law: { m, b in Laws.isOrdered({ m.apply($0, by: $1) }, b, less) }, mutant),
                "ordering is blind to \(mutant.rawValue) — that is the finding"
            )
        }
    }

    @Test("ordering catches direction and key errors that permutation cannot")
    func orderingCatchesWhatPermutationCannot() {
        let less = Comparators.byScoreThenName

        for mutant in [Sorts.Mutant.ascendingInsteadOfDescending, .sortsByNameNotScore, .returnsInputUnchanged] {
            #expect(
                Self.kills(law: { m, b in Laws.isOrdered({ m.apply($0, by: $1) }, b, less) }, mutant),
                "ordering must reject \(mutant.rawValue)"
            )
            // A reordering is still a permutation — so permutation alone is not enough.
            #expect(
                !Self.kills(law: { m, b in Laws.isPermutation({ m.apply($0, by: $1) }, b, less) }, mutant),
                "permutation is blind to \(mutant.rawValue) — the two laws are complements"
            )
        }
    }

    /// The pair above is the fixture's headline: **neither law subsumes the other**, and a
    /// suite carrying only one of them reports green on half the mutant set.
    @Test("leavesLastElementUnsorted needs ordering; idempotence alone misses most")
    func idempotenceIsTheWeakestOfTheThree() {
        let less = Comparators.byScoreThenName
        #expect(
            Self.kills(law: { m, b in Laws.isOrdered({ m.apply($0, by: $1) }, b, less) }, .leavesLastElementUnsorted)
        )
        // Idempotence catches almost nothing here: most mutants are stable under
        // re-application, so applying them twice equals applying them once.
        let survivors = Sorts.Mutant.allCases.filter { mutant in
            !Self.kills(law: { m, b in Laws.idempotence({ m.apply($0, by: $1) }, b, less) }, mutant)
        }
        #expect(
            survivors.count >= 4,
            "idempotence is the weak law of the three — survivors: \(survivors.map(\.rawValue))"
        )
    }

    // MARK: - Arm A (preorder) — stability, and the model law that rescues it

    /// On arm A the two implementations genuinely disagree, and ONLY on ties.
    @Test("arm A: the differential law is refuted by ties")
    func differentialFailsOnTies() {
        var generator = Generators(seed: 0x71E5)
        let boards = (0..<Self.trials).map { _ in generator.forcedTieBoard(playerCount: Self.players) }
        let refuted = boards.contains { !Laws.differential($0, Comparators.byScoreDescending) }
        #expect(refuted, "selection sort is unstable; the built-in is stable in practice")
    }

    /// ...and the model law holds on exactly those inputs. This is the recommendation
    /// from `fixtures/equatable-signal` demonstrated rather than restated.
    @Test("arm A: the SAME inputs satisfy the model law")
    func modelLawSurvivesWhereDifferentialFails() {
        var generator = Generators(seed: 0x71E5)
        let boards = (0..<Self.trials).map { _ in generator.forcedTieBoard(playerCount: Self.players) }
        for board in boards {
            #expect(
                Laws.differentialUnderScoreProjection(board, Comparators.byScoreDescending),
                "the disagreement is entirely inside tie groups"
            )
        }
    }

    /// Arm B has no ties to expose, so the same differential law is TRUE — and therefore
    /// says nothing about stability. Two arms, one line apart, opposite verdicts.
    @Test("arm B: the differential law holds, because the order is total")
    func differentialHoldsUnderTotalOrder() {
        var generator = Generators(seed: 0x71E5)
        for _ in 0..<Self.trials {
            let board = generator.realisticBoard(playerCount: Self.players)
            #expect(Laws.differential(board, Comparators.byScoreThenName))
        }
    }

    // MARK: - The comparator mutants

    @Test("the broken disjunctive comparator is not a strict weak ordering")
    func disjunctiveComparatorIsRefuted() {
        let sample = [
            PlayerScore(name: "z", score: 5),
            PlayerScore(name: "a", score: 3),
            PlayerScore(name: "m", score: 4)
        ]
        #expect(!Laws.isStrictWeakOrdering(Comparators.brokenDisjunctive, over: sample))
        #expect(Laws.isStrictWeakOrdering(Comparators.byScoreThenName, over: sample))
    }

    @Test("the non-strict comparator fails irreflexivity")
    func nonStrictComparatorIsRefuted() {
        let sample = [PlayerScore(name: "a", score: 1)]
        #expect(!Laws.isStrictWeakOrdering(Comparators.nonStrict, over: sample))
    }
}
