import SwiftInferCore

extension TemplateRegistry {

    /// Differential / oracle family — reference vs variant implementation.
    /// A separate pairing pass because its type filter is nothing like the
    /// inverse-shape one: the two halves have the SAME direction, not opposite
    /// ones. See `VariantPairing`.
    static func collectDifferential(
        _ summaries: [FunctionSummary],
        _ typeDecls: [TypeDecl],
        into collector: inout SuggestionCollector
    ) {
        for pair in VariantPairing.candidates(in: summaries, typeDecls: typeDecls) {
            if let suggestion = DifferentialTemplate.suggest(for: pair) {
                collector.record(suggestion)
            }
        }
    }
}
