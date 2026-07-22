import PropertyLawCore
import SwiftInferCore

/// B3 — the collectors for the shapes **application code** actually has.
///
/// The catalogue was algebraic and calibrated on libraries, whose interesting surface *is* an
/// algebra. An app is not shaped like that: its most valuable properties are that the chunks tile the
/// payload, that the comparator is a strict weak ordering, and that navigating in and back out leaves
/// you where you began. None of those is a semigroup, and none of them could be said.
///
/// Carved into its own file because `TemplateRegistry+Collection.swift` is at its length limit —
/// these belong together anyway, being the answer to one question.
extension TemplateRegistry {

    /// B3 — the partition / tiling law: the parts must reconstitute the whole.
    ///
    /// The catalogue was algebraic and calibrated on libraries. Application code is not shaped like
    /// an algebra: the most valuable property in a file-sync client is not a semigroup, it is *the
    /// chunks tile the payload exactly* — and no template in the set could say it. That gap is why a
    /// real app produced six suggestions and **zero refutable claims**.
    static func collectPartitionSuggestions(
        summaries: [FunctionSummary],
        into collector: inout SuggestionCollector
    ) {
        for shape in PartitionPairing.candidates(in: summaries) {
            if let suggestion = PartitionTemplate.suggest(for: shape) {
                collector.record(suggestion, generatorType: shape.typeName)
            }
        }
    }

    /// B3 — every application shape in one entry point: partition, comparator, predicate, state
    /// machine.
    static func collectApplicationShapeSuggestions(
        summaries: [FunctionSummary],
        shapesByName: [String: TypeShape],
        into collector: inout SuggestionCollector
    ) {
        collectPartitionSuggestions(summaries: summaries, into: &collector)
        collectSingleFunctionAppShapes(summaries: summaries, into: &collector)
        collectStateMachineSuggestions(summaries: summaries, into: &collector)
        collectSelectionSubsetSuggestions(summaries: summaries, shapesByName: shapesByName, into: &collector)
    }

    /// A `(…, Container) -> [T]` named like a selection, where the container is a
    /// corpus type with a `[T]` member: it owes `Set(result) ⊆ Set(container.<member>)`.
    /// Shapes-aware, so it is its own pass rather than part of the shapes-free
    /// single-function registry — the gap that left `layerChain` on the
    /// `f(x)==f(x)` tautology (see `docs/roadtest-swiftlintrulestudio.md`).
    private static func collectSelectionSubsetSuggestions(
        summaries: [FunctionSummary],
        shapesByName: [String: TypeShape],
        into collector: inout SuggestionCollector
    ) {
        for summary in summaries {
            if let suggestion = SelectionSubsetTemplate.suggest(for: summary, shapesByName: shapesByName) {
                collector.record(
                    suggestion,
                    generatorType: SelectionSubsetTemplate.containerType(for: summary, shapesByName: shapesByName)
                )
            }
        }
    }

    /// The single-function application shapes — involution, reorder-partition,
    /// filter-subset, and the `(T, T) -> Bool` trio (equivalence ▷ comparator ▷
    /// predicate) — driven from `singleFunctionAppShapes`, the one list that both
    /// wires them and is iterated by `ApplicationShapeRegistryTests`. Replaces four
    /// hand-written passes whose `collector.record` branches drifted out of test
    /// coverage one template at a time (see `docs/roadtest-swiftlintrulestudio.md`).
    ///
    /// Behaviour is preserved exactly: the same (summary, template) records with
    /// the same `generatorType`, and the trio's "stronger law wins the shared
    /// shape" is the `exclusionGroup` first-match-wins (equivalence before
    /// comparator before predicate) that the old `else if` chain encoded.
    private static func collectSingleFunctionAppShapes(
        summaries: [FunctionSummary],
        into collector: inout SuggestionCollector
    ) {
        for summary in summaries {
            var firedGroups: Set<Int> = []
            for template in singleFunctionAppShapes {
                if let group = template.exclusionGroup, firedGroups.contains(group) { continue }
                guard let suggestion = template.suggest(summary) else { continue }
                collector.record(suggestion, generatorType: template.generatorType(summary))
                if let group = template.exclusionGroup { firedGroups.insert(group) }
            }
        }
    }

    /// Two void-returning mutators that move one state machine in opposite directions.
    private static func collectStateMachineSuggestions(
        summaries: [FunctionSummary],
        into collector: inout SuggestionCollector
    ) {
        for pair in InverseMutatorPairing.candidates(in: summaries) {
            if let suggestion = StateMachineTemplate.suggest(for: pair) {
                collector.record(suggestion, generatorType: pair.forward.containingTypeName)
            }
        }
    }
}
