import SwiftInferCore

// Corroborate-only docstring signal for associativity. A docstring that asserts
// associativity ("associative", "grouping doesn't matter", …) earns +15 AND
// counts as the corroboration the unsupported-shape counter demands — so a
// documented associative op on a bare `(T,T)->T` shape surfaces (30 + 15 = 45,
// Likely) instead of being suppressed. Negation-gated; the shape still gates.
extension AssociativityTemplate {

    static func docstringCorroborationSignal(for summary: FunctionSummary) -> Signal? {
        guard let corroboration = DocstringPropertyCorroborator.corroboration(
            for: .associativity,
            in: summary.docComment
        ) else {
            return nil
        }
        return Signal(
            kind: .docstringCorroboration,
            weight: 15,
            detail: "Docstring corroborates associativity: '\(corroboration.matchedPhrase)'"
        )
    }
}
