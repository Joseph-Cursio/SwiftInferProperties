import OrderedCollections
@testable import OrderedSetGeneratorDomain
import Testing

/// The measurement. Every assertion here is a cell of `README.md`'s mutant
/// table, so the table cannot drift from the code that produced it.
@Suite("OrderedSet generator domain — current vs widened")
struct DomainArmsTests {

    // MARK: - Group A: the mutants the current domain cannot reach

    /// The headline, and it is **exhaustive rather than sampled**: `current` has
    /// 101 reachable values, so "this mutant survives" is a statement about the
    /// whole domain, not about a trial budget.
    @Test(
        "every domain-narrowness mutant survives the ENTIRE current domain",
        arguments: [Subject.arithmeticSeriesShortcut, .fixedArityFour, .nonNegativeAssumption]
    )
    func mutantsSurviveCurrentDomainExhaustively(subject: Subject) {
        let outcome = checkTotalLawExhaustivelyOverCurrentDomain(subject: subject)
        #expect(
            outcome.passed,
            """
            \(subject.rawValue) was caught over the current domain at value \(outcome.trialsRun) \
            (\(outcome.counterexample ?? "")). The premise of this fixture is that it cannot be, \
            so either the mutant or the domain model is wrong.
            """
        )
        #expect(outcome.trialsRun == 101, "the exhaustive arm must cover all 101 reachable values")
    }

    /// The other half of the A/B. Same mutants, same law, same driver, same
    /// seed — only the domain differs.
    @Test(
        "every one of those mutants is caught by the widened domain",
        arguments: [Subject.arithmeticSeriesShortcut, .fixedArityFour, .nonNegativeAssumption]
    )
    func widenedDomainCatchesThem(subject: Subject) {
        let outcome = checkTotalLaw(subject: subject, domain: .widened)
        print("  [widened/\(subject.rawValue)] caught @ trial \(outcome.trialsRun): \(outcome.counterexample ?? "-")")
        #expect(
            !outcome.passed,
            "\(subject.rawValue) survived 2,000 trials of the widened domain"
        )
    }

    /// Parity with the kit's own generator, measured rather than assumed.
    @Test(
        "the kit's domain catches them too",
        arguments: [Subject.arithmeticSeriesShortcut, .fixedArityFour, .nonNegativeAssumption]
    )
    func kitDomainCatchesThem(subject: Subject) {
        let outcome = checkTotalLaw(subject: subject, domain: .kit)
        print("  [kit/\(subject.rawValue)] caught @ trial \(outcome.trialsRun)")
        #expect(!outcome.passed)
    }

    // MARK: - Group B: controls

    /// The control that stops this being a one-way ratchet: widening must not
    /// make a CORRECT subject refute. Without this, "the new domain catches more
    /// mutants" is satisfied by a domain that breaks everything.
    @Test("the correct subject refutes under no domain", arguments: Domain.allCases)
    func correctSubjectHolds(domain: Domain) {
        let outcome = checkTotalLaw(subject: .correct, domain: domain)
        #expect(outcome.passed, "correct subject refuted: \(outcome.counterexample ?? "")")
        #expect(outcome.trialsRun == 2_000)
    }

    /// The `index(after:)` hazard that set the arity floor. An empty receiver has
    /// no valid index to advance from, and these recipes serve monotonicity
    /// picks — so `widened` must never yield one. The `kit` arm is asserted to
    /// yield empties precisely to show the two generators differ on purpose.
    @Test("the widened domain never yields an empty set; the kit's does")
    func arityFloorHolds() {
        var generator = SeededGenerator(seed: 0x5EED_1234)
        var widenedEmpties = 0
        var kitEmpties = 0
        for _ in 1 ... 5_000 {
            if Domain.widened.sample(&generator).isEmpty { widenedEmpties += 1 }
            if Domain.kit.sample(&generator).isEmpty { kitEmpties += 1 }
        }
        #expect(widenedEmpties == 0, "widened yielded \(widenedEmpties) empty sets — index laws would trap")
        #expect(kitEmpties > 0, "the kit's 0...8 floor should reach empty; if not, the arms are not distinct")
    }

    // MARK: - Group C: what this change does NOT reach

    /// The honest negative result, and the reason it is a test rather than a
    /// sentence: **no domain here catches the order projection by independent
    /// draws**, because the failure needs two values to collide on their element
    /// set while differing in order, and independent draws over a 201-value
    /// alphabet essentially never do.
    ///
    /// This is the collision-dependence rule from CLAUDE.md, and it means
    /// widening the element generator is the wrong lever for this bug class.
    @Test("no domain catches the order projection by independent draws", arguments: Domain.allCases)
    func orderProjectionSurvivesIndependentDraws(domain: Domain) {
        let outcome = checkOrderProjectionLaw(domain: domain, pairing: .independent)
        #expect(
            outcome.passed,
            "\(domain.rawValue) caught it at trial \(outcome.trialsRun) — the negative result no longer holds"
        )
    }

    /// And the lever that DOES work, so the follow-up is named with evidence
    /// rather than proposed: a permuting **pair sampler** catches it immediately,
    /// on the current domain included. That is a harness change, not a generator
    /// change.
    @Test("a permuting pair sampler catches it on every domain", arguments: Domain.allCases)
    func permutedPairingCatchesOrderProjection(domain: Domain) {
        let outcome = checkOrderProjectionLaw(domain: domain, pairing: .permuted)
        #expect(!outcome.passed, "\(domain.rawValue) did not catch it even when permuting")
    }
}
