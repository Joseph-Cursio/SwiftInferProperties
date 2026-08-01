import Testing
@testable import LeaderboardSort

/// **The generator is the experiment.** Same law, same code, refuted or green depending
/// only on how wide the generator draws.
///
/// CLAUDE.md's rule: a property whose failure needs two generated values to COLLIDE is
/// invisible to a generator drawing from a realistic-width domain. Every prior
/// demonstration of that in this repo has been a negative one — a law that quietly passed.
/// Bowling is a rare positive control, because the real domain (`0...300`) is narrow
/// enough that ties arise on their own.
@Suite("Generator width — the collision rule, demonstrated both ways")
struct GeneratorWidthTests {

    private static let trials = 200
    private static let players = 5

    /// Narrow domain: ties arise, the stability defect is found.
    @Test("0...300 finds the tie — the realistic domain is narrow enough")
    func narrowDomainRefutes() {
        var generator = Generators(seed: 0xB0_1234)
        var firstRefutingTrial: Int?
        for trial in 0..<Self.trials {
            let board = generator.realisticBoard(playerCount: Self.players)
            if !Laws.differential(board, Comparators.byScoreDescending) {
                firstRefutingTrial = trial
                break
            }
        }
        #expect(firstRefutingTrial != nil, "a tie must arise within \(Self.trials) trials")
    }

    /// Wide domain: no two scores ever collide, so the identical law reports green.
    ///
    /// **This is the failure mode, not a curiosity.** The law is false, the code is
    /// unstable, and the suite is green — because the generator was chosen for the type
    /// rather than for the law.
    @Test("0...Int32.max never finds it — the same law, silently green")
    func wideDomainReportsGreenOnAFalseLaw() {
        var generator = Generators(seed: 0xB0_1234)
        for _ in 0..<Self.trials {
            let board = generator.wideBoard(playerCount: Self.players)
            #expect(
                Laws.differential(board, Comparators.byScoreDescending),
                "no collision in a wide domain — so nothing to find"
            )
        }
    }

    /// The control that makes the green above interpretable: forcing ties proves the
    /// failure is reachable, so a green wide-domain run means "no collision arose", not
    /// "the property holds".
    @Test("forcing a tie proves the failure was reachable all along")
    func forcedTieProvesReachability() {
        var generator = Generators(seed: 0xB0_1234)
        let board = generator.forcedTieBoard(playerCount: Self.players)
        #expect(!Laws.differential(board, Comparators.byScoreDescending))
    }

    // MARK: - The collision rule relocated: names, not scores

    /// Unique names make `namesAreUnique` unfalsifiable. Same lesson, different subject —
    /// which is what "each player plays one game" costs the experiment.
    @Test("unique names make the uniqueness invariant unfalsifiable")
    func uniqueNamesNeverRefuteTheInvariant() {
        var generator = Generators(seed: 0x4E_11)
        for _ in 0..<Self.trials {
            let board = Leaderboard(entries: generator.realisticBoard(playerCount: Self.players))
            #expect(board.namesAreUnique)
        }
    }

    @Test("a colliding-name generator refutes it immediately")
    func duplicateNamesRefuteTheInvariant() {
        var generator = Generators(seed: 0x4E_11)
        let board = Leaderboard(entries: generator.duplicateNameBoard(playerCount: Self.players))
        #expect(!board.namesAreUnique)
    }

    /// **I had this dependency backwards, and the corrected version is the better finding.**
    ///
    /// The design claim was: arm B's comparator is total only BECAUSE names are unique, so
    /// breaking uniqueness silently degrades it to arm A's preorder. The test failed, and
    /// it was right to.
    ///
    /// Under MEMBERWISE equality, two entries sharing a name and a score are *the same
    /// value*. Swapping them is unobservable, so the sort result is still unique up to
    /// `==` and every law still holds. Duplicate names with DIFFERENT scores are still
    /// totally ordered, because score breaks the tie. **Uniqueness is a domain rule here,
    /// not a precondition for observable totality.**
    ///
    /// It becomes one the moment equality stops seeing the whole value — which is exactly
    /// `ProjectedPlayerScore`. There, two entries with the same score are `==` while
    /// carrying different names, so the sort can produce an order that `==` cannot
    /// distinguish but `.name` can.
    @Test("uniqueness is NOT a precondition under memberwise equality")
    func duplicateValuesAreIndistinguishable() {
        let colliding = [
            PlayerScore(name: "P0", score: 200),
            PlayerScore(name: "P0", score: 200),
            PlayerScore(name: "P1", score: 150)
        ]
        #expect(Laws.isOrdered(Sorts.builtinSorted, colliding, Comparators.byScoreThenName))
        // No DISTINCT incomparable pair exists: the two P0 entries are `==`.
        let incomparableDistinctPair = colliding.contains { lhs in
            colliding.contains { rhs in
                lhs != rhs
                    && !Comparators.byScoreThenName(lhs, rhs)
                    && !Comparators.byScoreThenName(rhs, lhs)
            }
        }
        #expect(!incomparableDistinctPair, "duplicates are the same value, so nothing is hidden")
    }

    /// ...and here is where uniqueness DOES bite. Same three entries, projecting equality:
    /// two distinct players compare `==`, so a sort may order them either way and the
    /// equality laws cannot see which. This is the `storedFieldProjection` blindness that
    /// `fixtures/equatable-signal` measured, reached from the sort side.
    @Test("under PROJECTING equality, distinct players become incomparable")
    func projectionHidesTheDistinction() {
        let lhs = ProjectedPlayerScore(name: "Ann", score: 200)
        let rhs = ProjectedPlayerScore(name: "Bob", score: 200)

        #expect(lhs == rhs, "projection: equal scores are equal values")
        #expect(lhs.name != rhs.name, "...while being observably different players")

        // The consequence: an order over the projection cannot distinguish them, so the
        // arrays [lhs, rhs] and [rhs, lhs] are `==` elementwise while presenting a
        // different leaderboard to a reader.
        #expect([lhs, rhs] == [rhs, lhs])
    }
}
