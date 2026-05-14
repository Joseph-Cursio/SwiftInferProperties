import Foundation
import Testing
@testable import SwiftInferCore

@Suite("SuggestionRenderer — V1.64.C verify-evidence annotation")
struct SuggestionRendererVerifyEvidenceTests {

    // MARK: - Absent evidence is byte-identical to pre-v1.64 output

    @Test("nil evidence renders no Verify: line")
    func nilEvidenceRendersNoVerifyLine() {
        let suggestion = makeSuggestion(canonicalInput: "no-evidence")
        let withNil = SuggestionRenderer.render(suggestion, verifyEvidence: nil)
        let bare = SuggestionRenderer.render(suggestion)
        #expect(withNil == bare)
        #expect(!withNil.contains("Verify:"))
    }

    @Test("empty evidence map leaves the list render byte-identical")
    func emptyMapLeavesListRenderUnchanged() {
        let suggestions = [
            makeSuggestion(canonicalInput: "list-a"),
            makeSuggestion(canonicalInput: "list-b")
        ]
        #expect(
            SuggestionRenderer.render(suggestions, verifyEvidenceByIdentity: [:])
                == SuggestionRenderer.render(suggestions)
        )
    }

    // MARK: - Per-outcome glyph + label

    @Test("each outcome renders its glyph and label")
    func eachOutcomeRendersGlyphAndLabel() {
        let cases: [(VerifyEvidenceOutcome, String)] = [
            (.measuredBothPass, "✓ bothPass"),
            (.measuredEdgeCaseAdvisory, "⚠ edge-case advisory"),
            (.measuredDefaultFails, "✗ defaultFails (verify-disproven)"),
            (.measuredError, "! error"),
            (.architecturalCoveragePending, "· architectural-coverage-pending")
        ]
        let suggestion = makeSuggestion(canonicalInput: "outcome-glyphs")
        for (outcome, expectedFragment) in cases {
            let rendered = SuggestionRenderer.render(
                suggestion,
                verifyEvidence: makeEvidence(for: suggestion, outcome: outcome, detail: nil)
            )
            #expect(rendered.contains("Verify:    \(expectedFragment)"))
        }
    }

    @Test("detail is appended when present, omitted when nil")
    func detailIsAppendedWhenPresent() {
        let suggestion = makeSuggestion(canonicalInput: "detail-fragment")
        let withDetail = SuggestionRenderer.render(
            suggestion,
            verifyEvidence: makeEvidence(
                for: suggestion,
                outcome: .measuredBothPass,
                detail: "defaultTrials=100 edgeTrials=100 edgeSampled=6"
            )
        )
        #expect(withDetail.contains(
            "Verify:    ✓ bothPass — defaultTrials=100 edgeTrials=100 edgeSampled=6"
        ))
        let withoutDetail = SuggestionRenderer.render(
            suggestion,
            verifyEvidence: makeEvidence(for: suggestion, outcome: .measuredBothPass, detail: nil)
        )
        #expect(withoutDetail.contains("Verify:    ✓ bothPass\n"))
        #expect(!withoutDetail.contains("✓ bothPass —"))
    }

    // MARK: - Line position

    @Test("Verify: line sits between Sampling: and Identity:")
    func verifyLineSitsBetweenSamplingAndIdentity() {
        let suggestion = makeSuggestion(canonicalInput: "line-position")
        let rendered = SuggestionRenderer.render(
            suggestion,
            verifyEvidence: makeEvidence(for: suggestion, outcome: .measuredBothPass, detail: nil)
        )
        guard let samplingIdx = rendered.range(of: "Sampling:")?.lowerBound,
              let verifyIdx = rendered.range(of: "Verify:")?.lowerBound,
              let identityIdx = rendered.range(of: "Identity:")?.lowerBound else {
            Issue.record("Expected Sampling / Verify / Identity lines not all present")
            return
        }
        #expect(samplingIdx < verifyIdx)
        #expect(verifyIdx < identityIdx)
    }

    // MARK: - V1.65 — verified-tier promotion in the Score: line

    @Test("strong suggestion + bothPass evidence renders Score: N (Verified)")
    func strongPlusBothPassRendersVerified() {
        let suggestion = makeStrongSuggestion(canonicalInput: "promote-verified")
        let rendered = SuggestionRenderer.render(
            suggestion,
            verifyEvidence: makeEvidence(for: suggestion, outcome: .measuredBothPass, detail: nil)
        )
        #expect(rendered.contains("Score:    \(suggestion.score.total) (Verified)"))
    }

    @Test("strong suggestion + non-bothPass evidence stays Strong")
    func strongPlusNonBothPassStaysStrong() {
        let suggestion = makeStrongSuggestion(canonicalInput: "no-promote-strong")
        for outcome: VerifyEvidenceOutcome in [
            .measuredEdgeCaseAdvisory, .measuredDefaultFails, .measuredError,
            .architecturalCoveragePending
        ] {
            let rendered = SuggestionRenderer.render(
                suggestion,
                verifyEvidence: makeEvidence(for: suggestion, outcome: outcome, detail: nil)
            )
            #expect(rendered.contains("Score:    \(suggestion.score.total) (Strong)"))
        }
    }

    @Test("likely suggestion + bothPass evidence stays Likely — only strong promotes")
    func likelyPlusBothPassStaysLikely() {
        let suggestion = makeSuggestion(canonicalInput: "no-promote-likely")
        #expect(suggestion.score.tier == .likely)
        let rendered = SuggestionRenderer.render(
            suggestion,
            verifyEvidence: makeEvidence(for: suggestion, outcome: .measuredBothPass, detail: nil)
        )
        #expect(rendered.contains("Score:    \(suggestion.score.total) (Likely)"))
    }

    @Test("strong suggestion with no evidence stays Strong")
    func strongWithNoEvidenceStaysStrong() {
        let suggestion = makeStrongSuggestion(canonicalInput: "strong-no-evidence")
        let rendered = SuggestionRenderer.render(suggestion, verifyEvidence: nil)
        #expect(rendered.contains("Score:    \(suggestion.score.total) (Strong)"))
    }

    // MARK: - List render annotates by identity

    @Test("list render annotates only the matching suggestion")
    func listRenderAnnotatesOnlyMatchingSuggestion() {
        let verified = makeSuggestion(canonicalInput: "list-verified")
        let unverified = makeSuggestion(canonicalInput: "list-unverified")
        let map = [
            verified.identity.normalized: makeEvidence(
                for: verified,
                outcome: .measuredBothPass,
                detail: nil
            )
        ]
        let rendered = SuggestionRenderer.render(
            [verified, unverified],
            verifyEvidenceByIdentity: map
        )
        // Exactly one Verify: line — the matched suggestion's.
        #expect(rendered.components(separatedBy: "Verify:").count == 2)
        #expect(rendered.contains("Verify:    ✓ bothPass"))
    }

    // MARK: - Helpers

    private func makeSuggestion(canonicalInput: String) -> Suggestion {
        Suggestion(
            templateName: "idempotence",
            evidence: [
                Evidence(
                    displayName: "normalize(_:)",
                    signature: "(String) -> String",
                    location: SourceLocation(file: "Sanitizer.swift", line: 7, column: 1)
                )
            ],
            score: Score(signals: [
                Signal(kind: .exactNameMatch, weight: 40, detail: "normalize")
            ]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(
                whySuggested: ["Curated idempotence verb match: 'normalize' (+40)"],
                whyMightBeWrong: []
            ),
            identity: SuggestionIdentity(canonicalInput: canonicalInput)
        )
    }

    /// A `.strong`-tier suggestion (signals sum to 90 ≥ 75) — the only
    /// tier that promotes to `.verified` under `.measuredBothPass`.
    private func makeStrongSuggestion(canonicalInput: String) -> Suggestion {
        let suggestion = Suggestion(
            templateName: "idempotence",
            evidence: [
                Evidence(
                    displayName: "normalize(_:)",
                    signature: "(String) -> String",
                    location: SourceLocation(file: "Sanitizer.swift", line: 7, column: 1)
                )
            ],
            score: Score(signals: [
                Signal(kind: .exactNameMatch, weight: 40, detail: "normalize"),
                Signal(kind: .typeSymmetrySignature, weight: 30, detail: "T -> T"),
                Signal(kind: .selfComposition, weight: 20, detail: "comp")
            ]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(
                whySuggested: ["Curated idempotence verb match: 'normalize' (+40)"],
                whyMightBeWrong: []
            ),
            identity: SuggestionIdentity(canonicalInput: canonicalInput)
        )
        precondition(suggestion.score.tier == .strong, "fixture must be Strong tier")
        return suggestion
    }

    private func makeEvidence(
        for suggestion: Suggestion,
        outcome: VerifyEvidenceOutcome,
        detail: String?
    ) -> VerifyEvidence {
        VerifyEvidence(
            identityHash: suggestion.identity.normalized,
            template: suggestion.templateName,
            outcome: outcome,
            detail: detail,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            swiftInferVersion: "1.64.0"
        )
    }
}
