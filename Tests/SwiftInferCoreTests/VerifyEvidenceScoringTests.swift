import Foundation
import Testing
@testable import SwiftInferCore

@Suite("VerifyEvidenceScoring — verify-as-signal post-pass (V1.66.A)")
struct VerifyEvidenceScoringTests {

    // MARK: - measuredBothPass → positive signal

    @Test("bothPass appends a verifyBothPass signal and raises the score total")
    func bothPassRaisesScore() {
        let suggestion = makeSuggestion(canonicalInput: "bothpass", signalWeight: 40)
        #expect(suggestion.score.total == 40)
        #expect(suggestion.score.tier == .likely)

        let result = VerifyEvidenceScoring.applied(
            to: [suggestion],
            evidenceByIdentity: evidenceMap(suggestion, .measuredBothPass)
        )[0]
        #expect(result.score.total == 40 + VerifyEvidenceScoring.verifyBothPassWeight)
        #expect(result.score.tier == .strong)
        #expect(result.score.signals.last?.kind == .verifyBothPass)
        #expect(result.explainability.whySuggested.contains { $0.contains("Verify: bothPass") })
        #expect(result.explainability.whyMightBeWrong == suggestion.explainability.whyMightBeWrong)
    }

    // MARK: - measuredDefaultFails → veto

    @Test("defaultFails appends a verifyDisproven veto and collapses the tier to suppressed")
    func defaultFailsVetoesSuggestion() {
        let suggestion = makeSuggestion(canonicalInput: "disproven", signalWeight: 90)
        #expect(suggestion.score.tier == .strong)

        let result = VerifyEvidenceScoring.applied(
            to: [suggestion],
            evidenceByIdentity: evidenceMap(suggestion, .measuredDefaultFails)
        )[0]
        #expect(result.score.isVetoed)
        #expect(result.score.tier == .suppressed)
        #expect(result.score.signals.last?.kind == .verifyDisproven)
        #expect(result.explainability.whyMightBeWrong.contains { $0.contains("Verify: defaultFails") })
        #expect(result.explainability.whyMightBeWrong.contains { $0.contains("(veto)") })
        #expect(result.explainability.whySuggested == suggestion.explainability.whySuggested)
    }

    // MARK: - score-neutral outcomes

    @Test("edgeCaseAdvisory, measuredError, and architecturalCoveragePending leave the suggestion unchanged")
    func scoreNeutralOutcomesPassThrough() {
        let suggestion = makeSuggestion(canonicalInput: "neutral", signalWeight: 60)
        for outcome: VerifyEvidenceOutcome in [
            .measuredEdgeCaseAdvisory, .measuredError, .architecturalCoveragePending
        ] {
            let result = VerifyEvidenceScoring.applied(
                to: [suggestion],
                evidenceByIdentity: evidenceMap(suggestion, outcome)
            )[0]
            #expect(result == suggestion)
        }
    }

    @Test("a suggestion with no matching evidence passes through unchanged")
    func noEvidencePassesThrough() {
        let suggestion = makeSuggestion(canonicalInput: "no-evidence", signalWeight: 50)
        let result = VerifyEvidenceScoring.applied(
            to: [suggestion],
            evidenceByIdentity: [:]
        )[0]
        #expect(result == suggestion)
    }

    // MARK: - advisory tier is skipped

    @Test("an .advisory-tier suggestion is never reshaped, even with bothPass evidence")
    func advisoryTierIsSkipped() {
        let advisory = Suggestion(
            templateName: "equivalence-class",
            evidence: [makeEvidence()],
            score: Score(advisorySignals: [
                Signal(kind: .discoverableAnnotation, weight: 10, detail: "advisory")
            ]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(whySuggested: ["advisory"], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "advisory-skip")
        )
        #expect(advisory.score.tier == .advisory)
        let result = VerifyEvidenceScoring.applied(
            to: [advisory],
            evidenceByIdentity: evidenceMap(advisory, .measuredBothPass)
        )[0]
        #expect(result == advisory)
    }

    // MARK: - order preservation

    @Test("applied preserves input order across a mixed batch")
    func orderPreserved() {
        let first = makeSuggestion(canonicalInput: "order-1", signalWeight: 40)
        let second = makeSuggestion(canonicalInput: "order-2", signalWeight: 90)
        let third = makeSuggestion(canonicalInput: "order-3", signalWeight: 50)
        let result = VerifyEvidenceScoring.applied(
            to: [first, second, third],
            evidenceByIdentity: evidenceMap(second, .measuredDefaultFails)
        )
        #expect(result.map(\.identity.normalized) == [
            first.identity.normalized,
            second.identity.normalized,
            third.identity.normalized
        ])
        #expect(result[0] == first)
        #expect(result[2] == third)
        #expect(result[1].score.tier == .suppressed)
    }

    // MARK: - Helpers

    private func makeEvidence() -> Evidence {
        Evidence(
            displayName: "normalize(_:)",
            signature: "(String) -> String",
            location: SourceLocation(file: "Sanitizer.swift", line: 7, column: 1)
        )
    }

    private func makeSuggestion(canonicalInput: String, signalWeight: Int) -> Suggestion {
        Suggestion(
            templateName: "idempotence",
            evidence: [makeEvidence()],
            score: Score(signals: [
                Signal(kind: .exactNameMatch, weight: signalWeight, detail: "normalize")
            ]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(
                whySuggested: ["Curated idempotence verb match: 'normalize' (+\(signalWeight))"],
                whyMightBeWrong: []
            ),
            identity: SuggestionIdentity(canonicalInput: canonicalInput)
        )
    }

    private func evidenceMap(
        _ suggestion: Suggestion,
        _ outcome: VerifyEvidenceOutcome
    ) -> [String: VerifyEvidence] {
        [
            suggestion.identity.normalized: VerifyEvidence(
                identityHash: suggestion.identity.normalized,
                template: suggestion.templateName,
                outcome: outcome,
                detail: outcome == .measuredBothPass
                    ? "defaultTrials=100 edgeTrials=100 edgeSampled=6"
                    : (outcome == .measuredDefaultFails ? "trial=7" : nil),
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                swiftInferVersion: "1.66.0"
            )
        ]
    }
}
