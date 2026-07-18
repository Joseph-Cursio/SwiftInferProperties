import SwiftInferCore

// Corroborate-only docstring signal for idempotence. Kept in its own file so the
// primary template stays under SwiftLint's file_length cap.
extension IdempotenceTemplate {

    /// Corroborate-only docstring signal (+15). Fires when the function's
    /// docstring independently asserts idempotence (`idempotent`, `no further
    /// effect`, `canonical form`, …) — raising a shape-matched candidate's tier
    /// (typically Possible 30 → Likely 45, so a documented-but-not-curated-name
    /// idempotent transform surfaces by default). Never surfaces a law the shape
    /// didn't already match; negation-gated at the source.
    static func docstringCorroborationSignal(for summary: FunctionSummary) -> Signal? {
        guard let corroboration = DocstringPropertyCorroborator.corroboration(
            for: .idempotence,
            in: summary.docComment
        ) else {
            return nil
        }
        return Signal(
            kind: .docstringCorroboration,
            weight: 15,
            detail: "Docstring corroborates idempotence: '\(corroboration.matchedPhrase)'"
        )
    }
}
