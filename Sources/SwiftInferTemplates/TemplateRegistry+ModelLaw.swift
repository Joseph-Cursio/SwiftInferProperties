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
        inheritedTypesByName: [String: Set<String>],
        into collector: inout SuggestionCollector
    ) {
        for shape in ModelLawPairing.candidates(in: summaries) {
            if let suggestion = ModelLawTemplate.suggest(for: shape) {
                collector.record(suggestion, generatorType: shape.typeName)
            }
        }
        collectSequenceViewModelLawSuggestions(
            summaries: summaries,
            inheritedTypesByName: inheritedTypesByName,
            into: &collector
        )
    }

    /// The second model-law family — `(a == b) == a.elementsEqual(b)`.
    ///
    /// Separate from the membership fan-out above because it keys on an entirely different
    /// input: membership needs a `contains` predicate on the carrier, this needs the carrier's
    /// **conformances**, routed through `OrderedCarrierDiscriminator`. The two share the
    /// "model law" name and nothing else.
    static func collectSequenceViewModelLawSuggestions(
        summaries: [FunctionSummary],
        inheritedTypesByName: [String: Set<String>],
        into collector: inout SuggestionCollector
    ) {
        let shapes = SequenceViewModelPairing.candidates(
            in: summaries,
            inheritedTypesByName: inheritedTypesByName
        )
        for shape in shapes {
            if let suggestion = SequenceViewModelLawTemplate.suggest(for: shape) {
                collector.record(suggestion, generatorType: shape.typeName)
            }
        }
    }
}
