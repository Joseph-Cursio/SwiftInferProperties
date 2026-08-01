import Foundation
import PropertyLawCore
import SwiftInferCore

/// Split from `TemplateRegistry+Collection.swift` for `file_length`.
extension TemplateRegistry {

    /// The two type-shape-driven fan-outs. Split out for the same reason as
    /// `collectIdentityElementSuggestions`: to keep `collectSuggestions` inside
    /// the SwiftLint function-body budget as template fan-outs accumulate.
    static func collectShapeSuggestions(
        summaries: [FunctionSummary],
        typeDecls: [TypeDecl],
        context: CollectionResolverContext,
        into collector: inout SuggestionCollector
    ) {
        collectCodableRoundTripSuggestions(summaries: summaries, typeDecls: typeDecls, into: &collector)
        let shapePairs = TypeShapeBuilder.shapes(from: typeDecls).map { ($0.name, $0) }
        let shapesByName = Dictionary(shapePairs) { first, _ in first }
        collectApplicationShapeSuggestions(
            summaries: summaries,
            shapesByName: shapesByName,
            into: &collector
        )
        collectModelLawSuggestions(
            summaries: summaries,
            typeDecls: typeDecls,
            inheritedTypesByName: context.inheritedTypesByName,
            into: &collector
        )
    }
}
