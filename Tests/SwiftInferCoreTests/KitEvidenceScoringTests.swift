@testable import SwiftInferCore
import Testing

/// **Kit results feeding back into inference.**
///
/// Before this the toolchain was one-way: `discover` proposed, the kit ran, and nothing came
/// back. These pin the asymmetry the repo owner argued for — `==` correctness is the
/// Equatable laws' job, so inference is entitled to ASSUME it and only a refutation should
/// move a grade.
@Suite("Kit evidence — only refutation moves the score")
struct KitEvidenceScoringTests {

    private func suggestion(carrier: String, score: Int = 85) -> Suggestion {
        Suggestion(
            templateName: "idempotence",
            evidence: [
                Evidence(
                    displayName: "normalize(_:)",
                    signature: "(\(carrier)) -> \(carrier)",
                    location: SourceLocation(file: "F.swift", line: 1, column: 1)
                )
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: score, detail: "d")]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(whySuggested: ["s"], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "i|\(carrier)"),
            carrier: carrier,
            carrierTypeName: carrier
        )
    }

    private func refutedLog(_ type: String) -> KitEvidenceLog {
        KitEvidenceLog(outcomes: [
            KitLawOutcome(
                typeName: type, law: "Hashable.equalityConsistency",
                outcome: .failed, tier: .strict, counterexample: "(Ann,200) vs (Bob,200)"
            )
        ])
    }

    // MARK: - No evidence: the assumption stands

    @Test("no kit evidence leaves suggestions untouched")
    func emptyLogIsPassThrough() {
        let input = [suggestion(carrier: "Widget")]
        #expect(KitEvidenceScoring.applied(to: input, evidence: KitEvidenceLog()) == input)
    }

    @Test("evidence about a DIFFERENT type leaves this one untouched")
    func unrelatedEvidenceIsPassThrough() {
        let input = [suggestion(carrier: "Widget")]
        #expect(KitEvidenceScoring.applied(to: input, evidence: refutedLog("Other")) == input)
    }

    // MARK: - Confirmed: provenance, NOT points

    /// The asymmetry. A passing Equatable suite does not make `f(f(x)) == f(x)` truer — it
    /// makes testing it meaningful. So the score must not move.
    @Test("a confirmed oracle adds a line and leaves the score alone")
    func confirmedIsScoreNeutral() {
        let log = KitEvidenceLog(outcomes: [
            KitLawOutcome(typeName: "Widget", law: "Equatable.reflexivity", outcome: .passed, tier: .strict),
            KitLawOutcome(typeName: "Widget", law: "Hashable.equalityConsistency", outcome: .passed, tier: .strict)
        ])
        let graded = KitEvidenceScoring.applied(to: [suggestion(carrier: "Widget")], evidence: log)
        #expect(graded.first?.score.total == 85, "confirmation is provenance, not a boost")
        #expect(graded.first?.explainability.whySuggested.contains { $0.contains("verified oracle") } == true)
    }

    // MARK: - Refuted: the exception that moves the grade

    @Test("a refuted oracle demotes below the default cut, and says why")
    func refutedDemotes() {
        let graded = KitEvidenceScoring.applied(
            to: [suggestion(carrier: "Widget")], evidence: refutedLog("Widget")
        )
        #expect(graded.first?.score.total == 40, "85 - 45")
        let wrong = graded.first?.explainability.whyMightBeWrong ?? []
        #expect(wrong.contains { $0.contains("PROPERTYLAWKIT REFUTED") })
        #expect(wrong.contains { $0.contains("PREREQUISITE, not a refutation of the law") })
        #expect(wrong.contains { $0.contains("(Ann,200) vs (Bob,200)") }, "carry the counterexample")
    }

    /// Demote, never veto. The reader whose `==` is broken needs the diagnosis; an empty run
    /// would hide the one finding that matters.
    @Test("it demotes rather than vetoes — the suggestion survives to carry its diagnosis")
    func refutedNeverVetoes() {
        let graded = KitEvidenceScoring.applied(
            to: [suggestion(carrier: "Widget")], evidence: refutedLog("Widget")
        )
        #expect(graded.first?.score.tier != .suppressed)
    }

    // MARK: - The three exclusions, each measured rather than argued

    /// `fixtures/toolchain-coverage` measured a CORRECT type failing `Hashable.distribution`
    /// purely because the generator was narrowed to hunt a collision bug.
    @Test("a Heuristic-tier failure does not demote")
    func heuristicFailureIsIgnored() {
        let log = KitEvidenceLog(outcomes: [
            KitLawOutcome(typeName: "Widget", law: "Hashable.distribution", outcome: .failed, tier: .heuristic)
        ])
        let input = [suggestion(carrier: "Widget")]
        #expect(KitEvidenceScoring.applied(to: input, evidence: log) == input)
    }

    /// The author used the kit's `.intentionalViolation` to say the failure is the design.
    @Test("an expectedViolation does not demote")
    func expectedViolationIsIgnored() {
        let log = KitEvidenceLog(outcomes: [
            KitLawOutcome(
                typeName: "Widget", law: "Hashable.equalityConsistency",
                outcome: .expectedViolation, tier: .strict
            )
        ])
        let input = [suggestion(carrier: "Widget")]
        #expect(KitEvidenceScoring.applied(to: input, evidence: log) == input)
    }

    /// A broken `<` invalidates ordering laws, not equality-shaped ones.
    @Test("a Comparable failure is not an equality-oracle refutation")
    func comparableFailureIsNotAnEqualityRefutation() {
        let log = KitEvidenceLog(outcomes: [
            KitLawOutcome(typeName: "Widget", law: "Comparable.totalOrder", outcome: .failed, tier: .strict)
        ])
        let input = [suggestion(carrier: "Widget")]
        #expect(KitEvidenceScoring.applied(to: input, evidence: log) == input)
    }

    @Test("generic parameters are stripped so Box<Int> matches a run recorded as Box")
    func genericsAreStripped() {
        let graded = KitEvidenceScoring.applied(
            to: [suggestion(carrier: "Box<Int>")], evidence: refutedLog("Box")
        )
        #expect(graded.first?.score.total == 40)
    }
}
