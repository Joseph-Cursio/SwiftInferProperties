import SwiftInferCore

// Corroborate-only docstring signal for monotonicity. Monotonicity is
// Possible-tier by default (§5.2); a docstring that asserts it ("monotone",
// "order-preserving", "non-decreasing", …) earns +15 and lifts a documented
// shape-match to Likely — the prose analog of the @CheckProperty(.monotonic)
// escalation. Negation-gated; the ordered-codomain shape still gates.
extension MonotonicityTemplate {

    static func docstringCorroborationSignal(for summary: FunctionSummary) -> Signal? {
        guard let corroboration = DocstringPropertyCorroborator.corroboration(
            for: .monotonicity,
            in: summary.docComment
        ) else {
            return nil
        }
        return Signal(
            kind: .docstringCorroboration,
            weight: 15,
            detail: "Docstring corroborates monotonicity: '\(corroboration.matchedPhrase)'"
        )
    }
}
