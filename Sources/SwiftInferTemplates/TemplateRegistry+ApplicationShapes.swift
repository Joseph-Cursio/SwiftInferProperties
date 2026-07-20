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
        into collector: inout SuggestionCollector
    ) {
        collectPartitionSuggestions(summaries: summaries, into: &collector)
        collectFunctionShapeSuggestions(summaries: summaries, into: &collector)
        collectStateMachineSuggestions(summaries: summaries, into: &collector)
        collectInvolutionSuggestions(summaries: summaries, into: &collector)
        collectReorderPartitionSuggestions(summaries: summaries, into: &collector)
    }

    /// The *reorder* sense of "partition": a `mutating` method that rearranges its
    /// elements around a predicate and returns the pivot. Disjoint from the tiling
    /// `collectPartitionSuggestions` above — same word, a different law — so it is
    /// its own pass rather than folded into `PartitionPairing`.
    private static func collectReorderPartitionSuggestions(
        summaries: [FunctionSummary],
        into collector: inout SuggestionCollector
    ) {
        for summary in summaries {
            if let suggestion = ReorderPartitionTemplate.suggest(for: summary) {
                collector.record(suggestion, generatorType: summary.containingTypeName)
            }
        }
    }

    /// A unary `(T) -> T` named like an involution: it owes `f(f(x)) == x`. Kept
    /// separate from the `(T, T) -> Bool` comparator/predicate loop because it is
    /// a different shape, and separate from idempotence because it is a different
    /// law over the same shape — the reason these names are vetoed from it.
    private static func collectInvolutionSuggestions(
        summaries: [FunctionSummary],
        into collector: inout SuggestionCollector
    ) {
        for summary in summaries {
            if let suggestion = InvolutionTemplate.suggest(for: summary) {
                collector.record(suggestion, generatorType: summary.returnTypeText)
            }
        }
    }

    /// The comparator and the predicate: two roles that share a signature and are told apart by their
    /// argument labels.
    private static func collectFunctionShapeSuggestions(
        summaries: [FunctionSummary],
        into collector: inout SuggestionCollector
    ) {
        for summary in summaries {
            if let suggestion = EquivalenceRelationTemplate.suggest(for: summary) {
                // Checked first: a named equality (`equals(_:_:)` positional /
                // `equals(to:)` labelled) would otherwise be mis-read as a comparator or a
                // predicate. Its law (reflexivity/symmetry/transitivity) is the specific one.
                collector.record(suggestion, generatorType: summary.parameters.first?.typeText)
            } else if let suggestion = ComparatorTemplate.suggest(for: summary) {
                collector.record(suggestion, generatorType: summary.parameters.first?.typeText)
            } else if let suggestion = PredicateTemplate.suggest(for: summary) {
                // `else if` on purpose: a comparator is `(T, T) -> Bool` and so is a binary
                // predicate. The comparator's law is strictly stronger, so it wins the shape — and
                // reporting both would be one function wearing two hats.
                collector.record(suggestion, generatorType: summary.parameters.first?.typeText)
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
