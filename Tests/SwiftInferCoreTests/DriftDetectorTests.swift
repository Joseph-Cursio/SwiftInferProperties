import Foundation
import Testing
@testable import SwiftInferCore

@Suite("DriftDetector — Strong-tier-only diff against baseline + decisions (M6.5)")
struct DriftDetectorTests {

    // MARK: - Empty / no-changes paths

    @Test
    func emptyCurrentSuggestionsProducesNoWarnings() {
        let warnings = DriftDetector.warnings(
            currentSuggestions: [],
            baseline: .empty,
            decisions: .empty
        )
        #expect(warnings.isEmpty)
    }

    @Test
    func currentSuggestionsAlreadyInBaselineProduceNoWarnings() {
        let suggestion = makeStrongSuggestion(canonical: "in-baseline")
        let baseline = Baseline(entries: [
            BaselineEntry(
                identityHash: suggestion.identity.normalized,
                template: "idempotence",
                scoreAtSnapshot: 90,
                tier: .strong
            )
        ])
        let warnings = DriftDetector.warnings(
            currentSuggestions: [suggestion],
            baseline: baseline,
            decisions: .empty
        )
        #expect(warnings.isEmpty)
    }

    // MARK: - Strong-tier filter

    @Test
    func likelyTierSuggestionsAreSilent() {
        let suggestion = makeSuggestion(canonical: "likely", score: 70)
        #expect(suggestion.score.tier == .likely)
        let warnings = DriftDetector.warnings(
            currentSuggestions: [suggestion],
            baseline: .empty,
            decisions: .empty
        )
        #expect(warnings.isEmpty)
    }

    @Test
    func possibleTierSuggestionsAreSilent() {
        let suggestion = makeSuggestion(canonical: "possible", score: 30)
        #expect(suggestion.score.tier == .possible)
        let warnings = DriftDetector.warnings(
            currentSuggestions: [suggestion],
            baseline: .empty,
            decisions: .empty
        )
        #expect(warnings.isEmpty)
    }

    @Test
    func strongTierNotInBaselineProducesWarning() {
        let suggestion = makeStrongSuggestion(canonical: "strong-new")
        let warnings = DriftDetector.warnings(
            currentSuggestions: [suggestion],
            baseline: .empty,
            decisions: .empty
        )
        #expect(warnings.count == 1)
        #expect(warnings.first?.identityHash == suggestion.identity.normalized)
        #expect(warnings.first?.template == "idempotence")
    }

    // MARK: - Decisions suppression

    @Test
    func decisionRecordedAsAcceptedSuppressesWarning() throws {
        try assertDecisionSuppresses(.accepted)
    }

    @Test
    func decisionRecordedAsRejectedSuppressesWarning() throws {
        try assertDecisionSuppresses(.rejected)
    }

    @Test
    func decisionRecordedAsSkippedSuppressesWarning() throws {
        // Per M6 plan open decision #2: skipped means "decide later" but
        // the user has acknowledged the suggestion, so drift stays quiet.
        try assertDecisionSuppresses(.skipped)
    }

    // MARK: - Mixed corpus + ordering

    @Test
    func mixedCorpusOnlyReturnsStrongUnseenUndecided() {
        let strongNew = makeStrongSuggestion(canonical: "strong-new")
        let strongInBaseline = makeStrongSuggestion(canonical: "strong-in-baseline")
        let strongDecided = makeStrongSuggestion(canonical: "strong-decided")
        let likelyNew = makeSuggestion(canonical: "likely-new", score: 70)
        let baseline = Baseline(entries: [
            BaselineEntry(
                identityHash: strongInBaseline.identity.normalized,
                template: "idempotence",
                scoreAtSnapshot: 90,
                tier: .strong
            )
        ])
        let decisions = Decisions(records: [
            DecisionRecord(
                identityHash: strongDecided.identity.normalized,
                template: "idempotence",
                scoreAtDecision: 90,
                tier: .strong,
                decision: .skipped,
                timestamp: Date(timeIntervalSince1970: 0)
            )
        ])
        let warnings = DriftDetector.warnings(
            currentSuggestions: [strongNew, strongInBaseline, strongDecided, likelyNew],
            baseline: baseline,
            decisions: decisions
        )
        #expect(warnings.count == 1)
        #expect(warnings.first?.identityHash == strongNew.identity.normalized)
    }

    @Test
    func warningsPreserveCurrentSuggestionsOrder() {
        // discover already sorts deterministically; drift inherits.
        let first = makeStrongSuggestion(canonical: "first")
        let second = makeStrongSuggestion(canonical: "second")
        let third = makeStrongSuggestion(canonical: "third")
        let warnings = DriftDetector.warnings(
            currentSuggestions: [first, second, third],
            baseline: .empty,
            decisions: .empty
        )
        #expect(warnings.map(\.identityHash) == [
            first.identity.normalized,
            second.identity.normalized,
            third.identity.normalized
        ])
    }

    // MARK: - Warning line shape

    @Test
    func renderedLineMatchesByteStableGoldenShape() {
        let warning = DriftWarning(
            identityHash: "ABCDEF1234567890",
            displayName: "normalize(_:)",
            template: "idempotence",
            location: SourceLocation(file: "Sources/Lib/Sanitizer.swift", line: 12, column: 5)
        )
        #expect(warning.renderedLine() == "warning: drift: new Strong suggestion 0xABCDEF1234567890 for "
            + "normalize(_:) at Sources/Lib/Sanitizer.swift:12 — idempotence (no recorded decision)")
    }

    @Test
    func suggestionWithoutEvidenceFallsBackToUnknown() {
        // Defensive — production scanners always emit at least one
        // evidence row, but DriftWarning.init(suggestion:) needs to
        // be nil-safe so a malformed input doesn't crash drift.
        let suggestion = Suggestion(
            templateName: "idempotence",
            evidence: [],
            score: Score(signals: [Signal(kind: .typeSymmetrySignature, weight: 90, detail: "")]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "test")
        )
        let warning = DriftWarning(suggestion: suggestion)
        #expect(warning.displayName == "<unknown>")
        #expect(warning.location.file == "<unknown>")
    }

    // MARK: - Helpers

    private func assertDecisionSuppresses(_ decision: Decision) throws {
        let suggestion = makeStrongSuggestion(canonical: "decided")
        let decisions = Decisions(records: [
            DecisionRecord(
                identityHash: suggestion.identity.normalized,
                template: "idempotence",
                scoreAtDecision: 90,
                tier: .strong,
                decision: decision,
                timestamp: Date(timeIntervalSince1970: 0)
            )
        ])
        let warnings = DriftDetector.warnings(
            currentSuggestions: [suggestion],
            baseline: .empty,
            decisions: decisions
        )
        #expect(warnings.isEmpty)
    }

    private func makeStrongSuggestion(canonical: String) -> Suggestion {
        makeSuggestion(canonical: canonical, score: 90)
    }

    private func makeSuggestion(canonical: String, score: Int) -> Suggestion {
        let evidence = Evidence(
            displayName: "normalize(_:)",
            signature: "(String) -> String",
            location: SourceLocation(file: "Test.swift", line: 1, column: 1)
        )
        return Suggestion(
            templateName: "idempotence",
            evidence: [evidence],
            score: Score(signals: [Signal(kind: .typeSymmetrySignature, weight: score, detail: "")]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: canonical)
        )
    }
}
