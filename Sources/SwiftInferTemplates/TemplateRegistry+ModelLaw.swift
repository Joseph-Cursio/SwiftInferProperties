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
    /// Six independent family fan-outs. Each is one line here and its own helper below,
    /// because they share nothing but the name "model law" — membership keys on a
    /// `contains` predicate, sequence-view on conformances, the rest on curated verb
    /// tables. Collapsing them into one loop is what pushed this past its complexity cap
    /// on 2026-08-01.
    static func collectModelLawSuggestions(
        summaries: [FunctionSummary],
        typeDecls: [TypeDecl],
        inheritedTypesByName: [String: Set<String>],
        into collector: inout SuggestionCollector
    ) {
        collectMembershipModelLaws(summaries, into: &collector)
        collectMemberHomomorphisms(summaries, inheritedTypesByName, into: &collector)
        collectFunctorIdentityLaws(summaries, inheritedTypesByName, into: &collector)
        collectEndedAccessLaws(summaries, into: &collector)
        collectScaledUnitLaws(summaries, into: &collector)
        collectBulkIncrementalLaws(summaries, typeDecls, into: &collector)
        collectSetRelationLaws(summaries, into: &collector)
        collectSequenceViewModelLawSuggestions(
            summaries: summaries,
            inheritedTypesByName: inheritedTypesByName,
            into: &collector
        )
    }

    private static func collectMembershipModelLaws(
        _ summaries: [FunctionSummary],
        into collector: inout SuggestionCollector
    ) {
        for shape in ModelLawPairing.candidates(in: summaries) {
            if let suggestion = ModelLawTemplate.suggest(for: shape) {
                collector.record(suggestion, generatorType: shape.typeName)
            }
        }
    }

    /// The member form of the additive-measure homomorphism. Lives here rather than in
    /// the per-summary loop because it needs TWO members on one carrier — which is
    /// exactly why the original free-function gate reached nothing.
    private static func collectMemberHomomorphisms(
        _ summaries: [FunctionSummary],
        _ inheritedTypesByName: [String: Set<String>],
        into collector: inout SuggestionCollector
    ) {
        let shapes = HomomorphismMemberPairing.candidates(
            in: summaries, inheritedTypesByName: inheritedTypesByName
        )
        for shape in shapes {
            if let suggestion = HomomorphismTemplate.suggestMemberForm(for: shape) {
                collector.record(suggestion, generatorType: shape.typeName)
            }
        }
    }

    private static func collectFunctorIdentityLaws(
        _ summaries: [FunctionSummary],
        _ inheritedTypesByName: [String: Set<String>],
        into collector: inout SuggestionCollector
    ) {
        let shapes = FunctorIdentityPairing.candidates(
            in: summaries, inheritedTypesByName: inheritedTypesByName
        )
        for shape in shapes {
            if let suggestion = FunctorIdentityTemplate.suggest(for: shape) {
                collector.record(suggestion, generatorType: shape.typeName)
            }
        }
    }

    private static func collectEndedAccessLaws(
        _ summaries: [FunctionSummary],
        into collector: inout SuggestionCollector
    ) {
        for shape in EndedAccessPairing.candidates(in: summaries) {
            if let suggestion = EndedAccessRoundTripTemplate.suggest(for: shape) {
                collector.record(suggestion, generatorType: shape.typeName)
            }
        }
    }

    private static func collectScaledUnitLaws(
        _ summaries: [FunctionSummary],
        into collector: inout SuggestionCollector
    ) {
        for shape in ScaledUnitPairing.candidates(in: summaries) {
            if let suggestion = ScaledUnitConsistencyTemplate.suggest(for: shape) {
                collector.record(suggestion, generatorType: shape.typeName)
            }
        }
    }

    private static func collectBulkIncrementalLaws(
        _ summaries: [FunctionSummary],
        _ typeDecls: [TypeDecl],
        into collector: inout SuggestionCollector
    ) {
        for shape in BulkIncrementalPairing.candidates(in: summaries, typeDecls: typeDecls) {
            if let suggestion = BulkIncrementalTemplate.suggest(for: shape) {
                collector.record(suggestion, generatorType: shape.typeName)
            }
        }
    }

    private static func collectSetRelationLaws(
        _ summaries: [FunctionSummary],
        into collector: inout SuggestionCollector
    ) {
        for shape in SetRelationModelPairing.candidates(in: summaries) {
            if let suggestion = SetRelationModelLawTemplate.suggest(for: shape) {
                collector.record(suggestion, generatorType: shape.typeName)
            }
        }
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
