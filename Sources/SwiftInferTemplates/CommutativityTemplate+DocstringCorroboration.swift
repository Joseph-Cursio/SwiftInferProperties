import SwiftInferCore

// Corroborate-only docstring signal for commutativity. A docstring that asserts
// commutativity ("commutative", "order of the arguments doesn't matter", …) both
// earns +15 AND counts as the corroboration the B24 unsupported-shape counter
// demands — so a documented commutative op on a bare `(T,T)->T` shape surfaces
// (30 + 15 = 45, Likely) instead of being suppressed as shape-only. Negation-
// gated at the source; the shape still gates (a docstring alone surfaces nothing).
extension CommutativityTemplate {

    static func docstringCorroborationSignal(for summary: FunctionSummary) -> Signal? {
        guard let corroboration = DocstringPropertyCorroborator.corroboration(
            for: .commutativity,
            in: summary.docComment
        ) else {
            return nil
        }
        return Signal(
            kind: .docstringCorroboration,
            weight: 15,
            detail: "Docstring corroborates commutativity: '\(corroboration.matchedPhrase)'"
        )
    }
}
