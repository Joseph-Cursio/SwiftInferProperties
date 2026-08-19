import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// The EXPECTED TO HOLD verdict — a **visibility** class, never a claim about the code.
///
/// `plans/suspected-defect-verdict-scope.md` §11 measured that no static signal
/// separates "the guess was wrong" from "the code is wrong": the conjecture caveat fires
/// on 14 of 14 refutations, and a body-shape reader would suppress the real defects. So
/// the section states both readings, and these tests pin that it never states one.
@Suite("Refuted expectation — states the fork, never the blame")
struct RefutedExpectationTests {

    private static func record(
        hash: String,
        template: String,
        carrier: String,
        outcome: SwiftInferCommand.Verify.SurveyOutcome,
        counterexample: String? = nil
    ) -> SwiftInferCommand.Verify.SurveyRecord {
        SwiftInferCommand.Verify.SurveyRecord(
            identityHash: hash,
            templateName: template,
            primaryFunctionName: "combine(_:)",
            carrier: carrier,
            outcome: outcome,
            outcomeDetail: outcome == .measuredDefaultFails ? "trial=0" : "defaultTrials=100",
            counterexample: counterexample
        )
    }

    // MARK: - The classifier

    @Test("a Likely refutation with a counterexample states a fork")
    func likelyWithCounterexampleQualifies() {
        #expect(
            RefutedExpectation.statesAFork(
                tier: .likely, hasCounterexample: true, coverage: .notApplicable
            )
        )
        #expect(
            RefutedExpectation.statesAFork(
                tier: .strong, hasCounterexample: true, coverage: .full
            )
        )
    }

    /// The idea doc gated on `staticTier >= .strong`, which against this repo's
    /// `Comparable` — `verified` is the MINIMUM — selects the low tiers instead. Pinning
    /// the direction, because the mistake is invisible at the call site.
    @Test("the low tiers never qualify, whatever the counterexample")
    func lowTiersDoNotQualify() {
        for tier in [Tier.possible, .suppressed, .advisory] {
            #expect(
                !RefutedExpectation.statesAFork(
                    tier: tier, hasCounterexample: true, coverage: .notApplicable
                ),
                "\(tier) must not reach the read-these-first section"
            )
        }
    }

    @Test("a missing tier is conservative, not promoting")
    func missingTierDoesNotQualify() {
        #expect(
            !RefutedExpectation.statesAFork(
                tier: nil, hasCounterexample: true, coverage: .notApplicable
            )
        )
    }

    @Test("no counterexample, no fork to state")
    func counterexampleIsRequired() {
        #expect(
            !RefutedExpectation.statesAFork(
                tier: .likely, hasCounterexample: false, coverage: .notApplicable
            )
        )
    }

    /// A partial exploration can false-fail from the action space it excluded, so it is
    /// not a refutation anyone should be told to read first.
    @Test("partial coverage disqualifies; notApplicable does not")
    func partialCoverageDisqualifies() {
        #expect(
            !RefutedExpectation.statesAFork(
                tier: .strong, hasCounterexample: true, coverage: .partial
            )
        )
        #expect(
            RefutedExpectation.statesAFork(
                tier: .strong, hasCounterexample: true, coverage: .notApplicable
            )
        )
    }

    // MARK: - The rendering

    /// The two rows are `fixtures/planted-defect-arm`'s measured pair: one refutation that
    /// is a real defect and one that is a false law about correct code, at the SAME tier.
    /// They must land in the same section and be described identically — any wording that
    /// fits one and not the other is the bug this verdict exists to avoid.
    @Test("the measured defect and the measured false law are rendered alike")
    func bothReadingsAreRenderedForBothCases() {
        let rendered = ProveThenShowRenderer.render(
            [
                Self.record(
                    hash: "0xA1", template: "associativity", carrier: "BlendSummary",
                    outcome: .measuredDefaultFails, counterexample: "(2,1),(4,1),(6,1)"
                ),
                Self.record(
                    hash: "0xB2", template: "commutativity", carrier: "PathSegment",
                    outcome: .measuredDefaultFails, counterexample: "(\"a\",\"b\")"
                )
            ],
            tiers: ["0xA1": .likely, "0xB2": .likely]
        )
        #expect(rendered.contains("EXPECTED TO HOLD"))
        #expect(rendered.contains("BlendSummary"))
        #expect(rendered.contains("PathSegment"))
        // Both readings, and the statement that the tool cannot choose.
        #expect(rendered.contains("the law does not apply to this function"))
        #expect(rendered.contains("the function is wrong"))
        #expect(rendered.contains("cannot choose between them"))
    }

    /// **The wording guard, and it caught its own first draft.**
    ///
    /// The property is not "the word *bug* never appears" — reading 2 says the function is
    /// wrong, and it has to, or the fork has one prong. The property is that **neither
    /// reading ever appears without the other**, plus no verdict LABEL that asserts blame.
    /// The first version of this test banned the substring `is a bug` and failed on the
    /// tool's own correctly-hedged output, which is the difference between guarding a
    /// claim and guarding a vocabulary.
    @Test("neither reading is ever rendered without the other")
    func neverStatesOneReadingAlone() {
        let rendered = ProveThenShowRenderer.render(
            [
                Self.record(
                    hash: "0xA1", template: "commutativity", carrier: "PathSegment",
                    outcome: .measuredDefaultFails, counterexample: "(\"a\",\"b\")"
                )
            ],
            tiers: ["0xA1": .likely]
        )
        let first = rendered.contains(RefutedExpectation.readings[0])
        let second = rendered.contains(RefutedExpectation.readings[1])
        #expect(first == second, "one reading was rendered without the other")
        #expect(first, "the fork was not stated at all")

        // And no label that decides it for the reader.
        for banned in ["Suspected defect", "SUSPECTED", "suspected bug", "likely bug", "probable bug"] {
            #expect(
                !rendered.contains(banned),
                "the verdict asserts blame it cannot support: '\(banned)'"
            )
        }
    }

    /// A low-tier refutation stays in DISPROVEN — and DISPROVEN must still exist, or the
    /// split has quietly become a rename.
    @Test("a Possible refutation stays in DISPROVEN")
    func lowTierStaysDisproven() {
        let rendered = ProveThenShowRenderer.render(
            [
                Self.record(
                    hash: "0xC3", template: "idempotence", carrier: "SumSummary",
                    outcome: .measuredDefaultFails, counterexample: "x"
                )
            ],
            tiers: ["0xC3": .possible]
        )
        #expect(rendered.contains("DISPROVEN"))
        #expect(!rendered.contains("EXPECTED TO HOLD"))
        #expect(rendered.contains("Expected-to-hold 0"))
    }

    /// Without tiers nothing is promoted — the shape every existing caller still gets.
    @Test("no tier map leaves every refutation in DISPROVEN")
    func withoutTiersNothingIsPromoted() {
        let rendered = ProveThenShowRenderer.render([
            Self.record(
                hash: "0xD4", template: "commutativity", carrier: "Decisions",
                outcome: .measuredDefaultFails, counterexample: "x"
            )
        ])
        #expect(!rendered.contains("EXPECTED TO HOLD"))
        #expect(rendered.contains("DISPROVEN"))
    }

    /// The other four buckets are untouched.
    @Test("proven, unverifiable and inconclusive still render")
    func otherBucketsSurvive() {
        let rendered = ProveThenShowRenderer.render([
            Self.record(hash: "0x1", template: "idempotence", carrier: "A", outcome: .measuredBothPass),
            Self.record(
                hash: "0x2", template: "round-trip", carrier: "B",
                outcome: .architecturalCoveragePending
            ),
            Self.record(hash: "0x3", template: "predicate", carrier: "C", outcome: .measuredError)
        ])
        #expect(rendered.contains("PROVEN"))
        #expect(rendered.contains("UNVERIFIABLE"))
        #expect(rendered.contains("INCONCLUSIVE"))
    }
}

/// The interaction fold — built once the deferral's premise was re-read.
///
/// The deferral said the trap-attribution census measured "a 0-of-10 subject-code rate ...
/// the opposite of the algebraic base rate". That was a misreading:
/// `docs/measurements/interaction-trap-attribution-census.md` defines `.invariantCheck` as
/// *"the property is genuinely refuted"* and `.subjectCode` as the subject's own trap, so
/// **10 of 10 `.invariantCheck`, 0 `.subjectCode`** means zero harness artifacts — the
/// refutations are all genuine. That is a reason to surface them, not to defer them.
///
/// What the census does leave open is whether an MVVM/VIPER carrier could produce a
/// subject-code trap the parser conflates. `TrapOrigin` already answers that per run, so
/// the fold consults it rather than waiting for a corpus.
@Suite("Refuted expectation — the interaction surface's attribution clause")
struct RefutedExpectationAttributionTests {

    @Test("a genuine property violation states a fork")
    func propertyViolationQualifies() {
        #expect(
            RefutedExpectation.statesAFork(
                tier: .likely, hasCounterexample: true,
                coverage: .full, attribution: .propertyViolation
            )
        )
    }

    /// The subject falling over is not the property failing.
    @Test("a subject trap never reaches read-these-first")
    func subjectTrapDisqualifies() {
        #expect(
            !RefutedExpectation.statesAFork(
                tier: .strong, hasCounterexample: true,
                coverage: .full, attribution: .subjectTrap
            )
        )
    }

    /// The census's own rule: absence of the marker never convicts the subject, but it is
    /// not evidence of a property violation either. `unknown` is its own answer.
    @Test("an unattributable trap is not promoted")
    func unknownAttributionDisqualifies() {
        #expect(
            !RefutedExpectation.statesAFork(
                tier: .strong, hasCounterexample: true,
                coverage: .full, attribution: .unknown
            )
        )
    }

    /// **The arm-4 guard.** A clause that rejected everything would make the fold green and
    /// useless, and the algebraic surface must keep working — it passes `.notApplicable`.
    @Test("the algebraic surface is unaffected by the new clause")
    func algebraicSurfaceStillQualifies() {
        #expect(
            RefutedExpectation.statesAFork(
                tier: .likely, hasCounterexample: true,
                coverage: .notApplicable, attribution: .notApplicable
            )
        )
    }

    /// Partial coverage still disqualifies even a genuine violation: relaxed exploration
    /// can false-fail from the action space it excluded.
    @Test("partial coverage still disqualifies a genuine violation")
    func partialCoverageBeatsAttribution() {
        #expect(
            !RefutedExpectation.statesAFork(
                tier: .strong, hasCounterexample: true,
                coverage: .partial, attribution: .propertyViolation
            )
        )
    }
}
