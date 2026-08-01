import Testing
@testable import IntegerDivisionGenerator

/// The gate. Scope §8 resolves Q4's conversions to "a **local gated fixture**
/// pinned at the corpus SHA", and says the gate is what separates a fixture
/// from "a pile of local rewrites". These four suites are that gate: each
/// number in `README.md` is asserted here, so the finding cannot rot quietly.

@Suite("The law itself — verbatim from the corpus, on both domains")
struct LawHoldsTests {

    /// The whole conversion is worthless if the law stopped holding. Both
    /// domains run the corpus's assertions unchanged against the real standard
    /// library, including every boundary case the original never reached.
    @Test("The division identity holds on both domains", arguments: Domain.allCases)
    func lawHolds(domain: Domain) {
        var failures = 0
        var trials = 0
        DivisionDomain.generate(domain) { trial in
            trials += 1
            let observed = trial.divisor.dividingFullWidth((high: trial.high, low: trial.low))
            // Verbatim from the corpus arm:
            //   expectEqual(observed.quotient, q)
            //   expectEqual(observed.remainder, r)
            if observed.quotient != trial.quotient || observed.remainder != trial.remainder {
                failures += 1
            }
        }
        #expect(trials == DivisionDomain.trialCount)
        #expect(failures == 0, "the standard library is correct on this domain")
    }
}

@Suite("Coverage — what each domain reaches")
struct EdgeCoverageTests {

    private func hitCounts(_ domain: Domain, _ classes: [EdgeClass]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for edgeClass in classes {
            counts[edgeClass.name] = 0
        }
        DivisionDomain.generate(domain) { trial in
            for edgeClass in classes where edgeClass.matches(trial) {
                counts[edgeClass.name, default: 0] += 1
            }
        }
        return counts
    }

    /// The finding, pinned. Not "rarely" and not "under-samples" — the corpus's
    /// generator reaches **none** of these, and that is structural rather than
    /// unlucky: a divisor below 2^50 needs the top byte to be 0 or -1 *and* 56
    /// random bits to land low, which is about 2^-40 per draw against 256 draws.
    @Test("The original domain reaches ZERO of the 17 edge classes")
    func originalReachesNoEdges() {
        let counts = hitCounts(.original, EdgeClasses.all)
        for edgeClass in EdgeClasses.all {
            #expect(counts[edgeClass.name] == 0, "expected no coverage of \(edgeClass.name)")
        }
    }

    /// And the converted domain reaches all of them.
    @Test("The edge-rotating domain reaches ALL 17 edge classes")
    func convertedReachesEveryEdge() {
        let counts = hitCounts(.edgeRotating, EdgeClasses.all)
        for edgeClass in EdgeClasses.all {
            #expect((counts[edgeClass.name] ?? 0) > 0, "expected coverage of \(edgeClass.name)")
        }
    }

    /// The honest half of the comparison. The corpus's generator is not
    /// careless — its top-byte stratification covers the four sign quadrants
    /// perfectly, which random draws over the full range would not. It is
    /// stratified for sign and blind to magnitude, and the conversion must
    /// keep the half that works.
    @Test("Both domains cover all four sign quadrants", arguments: Domain.allCases)
    func signQuadrantsSurvive(domain: Domain) {
        let counts = hitCounts(domain, EdgeClasses.signQuadrants)
        for quadrant in EdgeClasses.signQuadrants {
            #expect((counts[quadrant.name] ?? 0) > 0, "\(domain) lost \(quadrant.name)")
        }
        // Still near-balanced after the edge budget is spent.
        let values = EdgeClasses.signQuadrants.compactMap { counts[$0.name] }
        let smallest = values.min() ?? 0
        let largest = values.max() ?? 0
        #expect(smallest * 2 >= largest, "quadrant balance collapsed: \(values)")
    }
}

@Suite("Refutability — the measurement that actually matters")
struct RefutationTests {

    /// Per mutant, the trial index at which the domain first refutes it, or
    /// `nil` if it never does.
    private func firstKills(_ domain: Domain) -> [String: Int?] {
        var kills: [String: Int?] = [:]
        for mutant in Mutants.all {
            kills[mutant.name] = Int?.none
        }
        var index = 0
        DivisionDomain.generate(domain) { trial in
            let correct = trial.divisor.dividingFullWidth((high: trial.high, low: trial.low))
            for mutant in Mutants.all where kills[mutant.name] == Int?.none {
                let observed = mutant.corrupt(trial, correct.quotient, correct.remainder)
                if observed.quotient != trial.quotient || observed.remainder != trial.remainder {
                    kills[mutant.name] = index
                }
            }
            index += 1
        }
        return kills
    }

    /// "Score refutability, not suggestion count." A coverage table only says
    /// the boundary values are now present; this says the test can catch things
    /// it previously could not. 2 of 8 becomes 8 of 8.
    @Test("The conversion strictly increases refutation power: 2/8 to 8/8")
    func refutationPowerIncreases() {
        let before = firstKills(.original)
        let after = firstKills(.edgeRotating)

        let killedBefore = Mutants.all.filter { before[$0.name] ?? nil != nil }
        let killedAfter = Mutants.all.filter { after[$0.name] ?? nil != nil }

        #expect(killedBefore.count == 2, "original killed \(killedBefore.map(\.name))")
        #expect(killedAfter.count == 8, "converted killed \(killedAfter.map(\.name))")

        // Strictly greater: nothing the original caught was lost. This is the
        // assertion that makes the table a comparison rather than a tally.
        for mutant in Mutants.all where (before[mutant.name] ?? nil) != nil {
            #expect((after[mutant.name] ?? nil) != nil, "\(mutant.name) was lost in conversion")
        }
    }

    /// The controls, isolated. Both interior mutants survive the conversion, so
    /// the six boundary kills were not bought with interior coverage.
    ///
    /// Deliberately asserts only that both domains kill them, **not** that the
    /// converted domain kills them sooner. It does kill M8 sooner (1,246 vs
    /// 7,763) but that is an artifact of which low words the edge substitutions
    /// happen to produce, not evidence of better interior sampling — pinning it
    /// would be reading noise as a result.
    @Test("Interior detection is not sacrificed", arguments: Domain.allCases)
    func interiorControlsStillDie(domain: Domain) {
        let kills = firstKills(domain)
        for mutant in Mutants.all where mutant.standsFor.hasPrefix("CONTROL") {
            #expect((kills[mutant.name] ?? nil) != nil, "\(domain) failed to kill \(mutant.name)")
        }
    }
}
