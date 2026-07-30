import Foundation
import SwiftInferCore

extension TemplateRegistry {

    /// The model law — an operation must agree with the semantics its name claims, checked
    /// pointwise through `contains`.
    ///
    /// Its own entry point rather than a line inside `collectApplicationShapeSuggestions`,
    /// because it is not an application shape: it is the answer to a **catalog** gap that two
    /// independent measurements converged on (see `ModelLawTemplate`). Keeping it separate
    /// also keeps `TemplateRegistry+ApplicationShapes.swift` under the file-length cap.
    static func collectModelLawSuggestions(
        summaries: [FunctionSummary],
        into collector: inout SuggestionCollector
    ) {
        for shape in ModelLawPairing.candidates(in: summaries) {
            if let suggestion = ModelLawTemplate.suggest(for: shape) {
                collector.record(suggestion, generatorType: shape.typeName)
            }
        }
    }
}
