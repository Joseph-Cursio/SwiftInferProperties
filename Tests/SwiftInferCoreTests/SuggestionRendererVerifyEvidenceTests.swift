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
