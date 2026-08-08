import SwiftInferCore

extension TemplateRegistry {

    /// Detail text rendered for the cross-validation signal when the corroborating test is
    /// not known. Retained as the degraded form — see `crossValidationDetail(for:)`.
    static var crossValidationDetail: String { "Cross-validated by TestLifter" }

    /// Detail text naming **which** test corroborates this law.
    ///
    /// The `+20` was designed to mean *this codebase independently states this law*. Once the
    /// slicer could read property tests, it could equally mean *this codebase took our
    /// advice* — and the two rendered identically. Measured: the four `merge(_:)`
    /// commutativity rows are corroborated by `MergeAlgebraPropertyTests`, whose own header
    /// says the laws were ones `discover` **proposed**
    /// (`docs/measurements/roadtest-self-dogfood-2026-08-08.md` §7.6).
    ///
    /// The fix is not to suppress the signal but to **name its source**, the same medicine
    /// §7.4 applied to lifted rows: a reader who can see the corroborating test can judge its
    /// independence, and a reader who cannot is being asked to take "cross-validated" on
    /// trust. This does not settle whether such corroboration *should* count — it makes the
    /// question answerable at the point of reading.
    static func crossValidationDetail(for origin: LiftedOrigin?) -> String {
        guard let origin, origin.sourceLocation.isResolvable else {
            return crossValidationDetail
        }
        return "\(crossValidationDetail) — \(origin.sourceLocation.file):"
            + "\(origin.sourceLocation.line) `\(origin.testMethodName)`"
    }

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
    /// `origins` is **advisory**: it changes only the rendered detail, never whether the
    /// signal fires. `keys` stays authoritative, so a key present without an origin still
    /// scores `+20` and renders the unqualified sentence — the two collections disagreeing
    /// can produce a vaguer message but never a wrong score.
    static func applyCrossValidation(
        to suggestions: [Suggestion],
        matching keys: Set<CrossValidationKey>,
        origins: [CrossValidationKey: LiftedOrigin] = [:]
    ) -> [Suggestion] {
        if keys.isEmpty {
            return suggestions
        }
        return suggestions.map { suggestion in
            guard keys.contains(suggestion.crossValidationKey) else {
                return suggestion
            }
            return rebuildWithCrossValidation(
                suggestion, origin: origins[suggestion.crossValidationKey]
            )
        }
    }

    private static func rebuildWithCrossValidation(
        _ suggestion: Suggestion,
        origin: LiftedOrigin?
    ) -> Suggestion {
        let signal = Signal(
            kind: .crossValidation,
            weight: 20,
            detail: crossValidationDetail(for: origin)
        )
        let newScore = Score(signals: suggestion.score.signals + [signal])
        let newWhy = suggestion.explainability.whySuggested + [signal.formattedLine]
        let newExplainability = ExplainabilityBlock(
            whySuggested: newWhy,
            whyMightBeWrong: suggestion.explainability.whyMightBeWrong
        )
        // Mutate a copy; never rebuild field-by-field. The comment this replaces was the SECOND
        // recorded instance of the same bug — "omitting them reset carrier, carrierTypeName,
        // liftedOrigin, and mockGenerator to nil, so any cross-validated suggestion lost its owner
        // + generator carrier before the index" — and the fix each time was to add the missing
        // field, which leaves the trap armed for the next one. It then ate `generatorRecipes`.
        var updated = suggestion
        updated.score = newScore
        updated.explainability = newExplainability
        return updated
    }

    /// Detail text rendered for the counter-signal Signal.
    static var counterSignalDetail: String {
        "Counter-signal: asymmetric assertion in test target"
    }

    /// M7 — walk `suggestions` and rebuild any whose
    /// `crossValidationKey` is in `keys`, appending a `-25
    /// .asymmetricAssertion` Signal and a matching `whyMightBeWrong`
    /// line. Suggestions outside the set pass through. The set is
    /// checked first so the fast path (empty set, no counter-signal)
    /// is a no-op.
    ///
    /// Sequenced AFTER `applyCrossValidation` per M7 plan OD #5 so
    /// suggestions both cross-validated AND counter-signaled land at
    /// `base+20-25 = base-5`, preserving the relative weighting
    /// (cross-validation `+20` < counter-signal `-25` in absolute
    /// terms).
    static func applyCounterSignal(
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
            return rebuildWithCounterSignal(suggestion)
        }
    }

    private static func rebuildWithCounterSignal(_ suggestion: Suggestion) -> Suggestion {
        let signal = Signal(
            kind: .asymmetricAssertion,
            weight: -25,
            detail: counterSignalDetail
        )
        let newScore = Score(signals: suggestion.score.signals + [signal])
        let newCaveats = suggestion.explainability.whyMightBeWrong + [signal.formattedLine]
        let newExplainability = ExplainabilityBlock(
            whySuggested: suggestion.explainability.whySuggested,
            whyMightBeWrong: newCaveats
        )
        var updated = suggestion
        updated.score = newScore
        updated.explainability = newExplainability
        return updated
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
