import Foundation
@testable import SwiftInferCore
import Testing

/// A refutation a HUMAN established outranks a measurement that found no counterexample.
///
/// **The gap road test §10.4 named.** `verifyDisproven` vetoes on `.measuredDefaultFails` — a
/// machine refutation — and nothing let a refutation a person wrote down re-enter the loop. So
/// `ViewModelNameHeuristics.booleanStem` rendered `Verified` while
/// `SurveyedIdempotencePropertyTests` existed solely to pin it as false.
///
/// **The counter-signal alone could not have fixed it.** `-25 .asymmetricAssertion` against
/// `+50` still nets positive — and decisively, the displayed `Verified` never came from the
/// score: `Tier.promoted(byVerifyOutcome:)` reads the outcome and ignores every signal, so no
/// demotion of any size could remove the label.
@Suite("An author's refutation outranks verify evidence")
struct AuthorContradictionTests {

    private func pick(contradicted: Bool) -> Suggestion {
        var signals = [Signal(kind: .typeSymmetrySignature, weight: 30, detail: "T -> T")]
        if contradicted {
            signals.append(
                Signal(kind: .asymmetricAssertion, weight: -25, detail: "a test asserts the negative")
            )
        }
        return Suggestion(
            templateName: "idempotence",
            evidence: [
                Evidence(
                    displayName: "booleanStem(_:)",
                    signature: "(String) -> String",
                    location: SourceLocation(file: "ViewModelNameHeuristics.swift", line: 53, column: 1)
                ),
            ],
            score: Score(signals: signals),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(whySuggested: ["shape"], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "idempotence|booleanStem")
        )
    }

    private func bothPass(for suggestion: Suggestion) -> [String: VerifyEvidence] {
        [
            suggestion.identity.normalized: VerifyEvidence(
                identityHash: suggestion.identity.normalized,
                template: "idempotence",
                outcome: .measuredBothPass,
                detail: "defaultTrials=100",
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                swiftInferVersion: "1.149.0",
                subjectFingerprint: "SAMEBODY00000000"
            ),
        ]
    }

    private func current(_ suggestion: Suggestion) -> [String: String] {
        [suggestion.identity.normalized: "SAMEBODY00000000"]
    }

    @Test("a contradicted law does not take the bothPass promotion")
    func contradictedLawIsNotPromoted() {
        let suggestion = pick(contradicted: true)
        let result = VerifyEvidenceScoring.applied(
            to: [suggestion],
            evidenceByIdentity: bothPass(for: suggestion),
            currentFingerprintByIdentity: current(suggestion)
        )[0]

        #expect(!result.score.signals.contains { $0.kind == .verifyBothPass })
        #expect(result.explainability.whyMightBeWrong.contains { $0.contains("asserts this law does NOT hold") })
    }

    /// The label is the whole point: a demotion could never have removed it.
    @Test("a contradicted law's evidence is filtered out of rendering, so it cannot show Verified")
    func contradictedLawCannotRenderVerified() {
        let suggestion = pick(contradicted: true)
        let filtered = VerifyEvidenceScoring.applicable(
            to: [suggestion],
            evidenceByIdentity: bothPass(for: suggestion),
            currentFingerprintByIdentity: current(suggestion)
        )
        #expect(filtered.isEmpty)

        let rendered = SuggestionRenderer.render(
            suggestion, verifyEvidence: filtered[suggestion.identity.normalized]
        )
        #expect(!rendered.contains("(Verified)"))
    }

    /// **The control.** Without the counter-signal the evidence must still apply, or this
    /// change would have switched verification off rather than qualified it.
    @Test("an uncontradicted law still promotes")
    func uncontradictedLawStillPromotes() {
        let suggestion = pick(contradicted: false)
        let result = VerifyEvidenceScoring.applied(
            to: [suggestion],
            evidenceByIdentity: bothPass(for: suggestion),
            currentFingerprintByIdentity: current(suggestion)
        )[0]

        #expect(result.score.signals.contains { $0.kind == .verifyBothPass })
        let filtered = VerifyEvidenceScoring.applicable(
            to: [suggestion],
            evidenceByIdentity: bothPass(for: suggestion),
            currentFingerprintByIdentity: current(suggestion)
        )
        #expect(filtered.count == 1)
    }
}
