import SwiftInferCore

extension TemplateRegistry {

    /// Detail text rendered for the M3.5 cross-validation signal. Kept
    /// generic for the dormant seam — once TestLifter M1 ships, the
    /// caller-side hook can pass a richer detail (e.g. the test name).
    static var crossValidationDetail: String { "Cross-validated by TestLifter" }

    /// Walk `suggestions` and rebuild any whose `identity` is in
    /// `identities`, appending a `+20` cross-validation signal and a
    /// matching `whySuggested` line. Suggestions outside the set pass
    /// through by reference equality. The set is checked first so the
    /// fast path (empty set, no cross-validation) is a no-op.
    static func applyCrossValidation(
        to suggestions: [Suggestion],
        matching identities: Set<SuggestionIdentity>
    ) -> [Suggestion] {
        if identities.isEmpty {
            return suggestions
        }
        return suggestions.map { suggestion in
            guard identities.contains(suggestion.identity) else {
                return suggestion
            }
            return rebuildWithCrossValidation(suggestion)
        }
    }

    private static func rebuildWithCrossValidation(_ suggestion: Suggestion) -> Suggestion {
        let signal = Signal(
            kind: .crossValidation,
            weight: 20,
            detail: crossValidationDetail
        )
        let newScore = Score(signals: suggestion.score.signals + [signal])
        let newWhy = suggestion.explainability.whySuggested + [signal.formattedLine]
        let newExplainability = ExplainabilityBlock(
            whySuggested: newWhy,
            whyMightBeWrong: suggestion.explainability.whyMightBeWrong
        )
        return Suggestion(
            templateName: suggestion.templateName,
            evidence: suggestion.evidence,
            score: newScore,
            generator: suggestion.generator,
            explainability: newExplainability,
            identity: suggestion.identity
        )
    }

    /// Sort suggestions by (file path, line) of the first evidence row,
    /// breaking ties by template name. Supports the byte-identical-
    /// reproducibility guarantee (PRD §16 #6) — every `discover` returns
    /// suggestions in deterministic order across runs.
    static func sortSuggestions(_ suggestions: [Suggestion]) -> [Suggestion] {
        suggestions.sorted(by: lessThan)
    }

    private static func lessThan(_ lhs: Suggestion, _ rhs: Suggestion) -> Bool {
        let lhsLoc = lhs.evidence.first?.location
        let rhsLoc = rhs.evidence.first?.location
        guard let lhsLoc, let rhsLoc else {
            return lhs.templateName < rhs.templateName
        }
        if lhsLoc.file != rhsLoc.file {
            return lhsLoc.file < rhsLoc.file
        }
        if lhsLoc.line != rhsLoc.line {
            return lhsLoc.line < rhsLoc.line
        }
        return lhs.templateName < rhs.templateName
    }
}
