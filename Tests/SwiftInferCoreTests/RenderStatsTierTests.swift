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
                ),
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
            ),
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
