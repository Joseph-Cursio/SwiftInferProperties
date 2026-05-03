import SwiftInferCore

extension TemplateRegistry {

    /// Detail text rendered for the cross-validation signal.
    static var crossValidationDetail: String { "Cross-validated by TestLifter" }

    /// Walk `suggestions` and rebuild any whose `crossValidationKey` is
    /// in `keys`, appending a `+20` cross-validation signal and a
    /// matching `whySuggested` line. Suggestions outside the set pass
    /// through by reference equality. The set is checked first so the
    /// fast path (empty set, no cross-validation) is a no-op.
    ///
    /// **TestLifter M1.4** widened the seam from `Set<SuggestionIdentity>`
    /// to `Set<CrossValidationKey>` — the lighter-weight key
    /// (template + sorted callee names) matches what TestLifter can
    /// extract from a test body without semantic resolution.
    static func applyCrossValidation(
        to suggestions: [Suggestion],
        matching keys: Set<CrossValidationKey>
    ) -> [Suggestion] {
        if keys.isEmpty {
            return suggestions
        }
        return suggestions.map { suggestion in
            guard keys.contains(suggestion.crossValidationKey) else {
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
