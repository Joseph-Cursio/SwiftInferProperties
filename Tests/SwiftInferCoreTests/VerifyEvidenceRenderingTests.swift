import Foundation
@testable import SwiftInferCore
import Testing

// Renderer-side guards for verify evidence. Split from `VerifyEvidenceStalenessTests.swift`
// when that file hit SwiftLint's 400-line cap; the seam is meaningful rather than arbitrary —
// that file asks whether evidence may be USED, these ask what the reader is SHOWN, and the
// gap between those two questions is exactly the defect §10.9 records.

/// `--stats-only` must be able to say `Verified`.
///
/// **It structurally could not until v1.149.** `renderStats` took no evidence parameter, so
/// the tier it printed fell back to `tier(forScore:)` — and a 100-point row is `Strong` there,
/// because `.verified` is set by the surfacing pipeline rather than derived from the score.
/// Measured on this repo: `SwiftInferCore` printed **"36 Strong"** where the truth was 33
/// Verified + 3 Strong, and `SwiftInferCLI` **"22"** where it was 18 + 4. Both add up exactly,
/// which is what made it a mechanism rather than a coincidence.
///
/// It is the view a CI dashboard reads, and it was both inflating `Strong` and hiding the
/// tool's best result.
@Suite("--stats-only reports the effective tier")
struct RenderStatsTierTests {

    private func suggestion(_ canonical: String) -> Suggestion {
        Suggestion(
            templateName: "idempotence",
            evidence: [
                Evidence(
                    displayName: "normalize(_:)",
                    signature: "(String) -> String",
                    location: SourceLocation(file: "S.swift", line: 1, column: 1)
                )
            ],
            // 90 lands squarely in Strong, so any move to Verified is the evidence talking.
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 90, detail: "n")]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(whySuggested: ["n"], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: canonical)
        )
    }

    private func bothPass(for pick: Suggestion) -> [String: VerifyEvidence] {
        [
            pick.identity.normalized: VerifyEvidence(
                identityHash: pick.identity.normalized,
                template: pick.templateName,
                outcome: .measuredBothPass,
                detail: "held",
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                swiftInferVersion: "1.149.0",
                subjectFingerprint: "SAMEBODY00000000"
            )
        ]
    }

    @Test("a bothPass row is reported as Verified, not folded into Strong")
    func bothPassReportsVerified() {
        let pick = suggestion("stats-verified")
        let stats = SuggestionRenderer.renderStats([pick], verifyEvidenceByIdentity: bothPass(for: pick))

        #expect(stats.contains("1 Verified"), "the execution-backed verdict must be visible")
        #expect(!stats.contains("Strong"), "and must not be reported as a static Strong score")
    }

    /// **The control**: with no evidence the line is unchanged, so existing output and goldens
    /// are unaffected by the new parameter.
    @Test("with no evidence the tier line is unchanged")
    func noEvidenceIsUnchanged() {
        let pick = suggestion("stats-strong")
        #expect(SuggestionRenderer.renderStats([pick]).contains("1 Strong"))
        #expect(
            SuggestionRenderer.renderStats([pick])
                == SuggestionRenderer.renderStats([pick], verifyEvidenceByIdentity: [:])
        )
    }

    /// The stats view and the full view must not disagree about a row's tier — the whole
    /// complaint was that a reader got a different answer depending on which they read.
    @Test("stats and full render agree on the effective tier")
    func statsAgreesWithFullRender() {
        let pick = suggestion("stats-agree")
        let evidence = bothPass(for: pick)
        let full = SuggestionRenderer.render(pick, verifyEvidence: evidence[pick.identity.normalized])

        #expect(full.contains("(Verified)"))
        #expect(SuggestionRenderer.renderStats([pick], verifyEvidenceByIdentity: evidence).contains("1 Verified"))
    }
}

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
                )
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
            )
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
