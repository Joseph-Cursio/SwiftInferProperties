import SwiftInferCore

extension TemplateRegistry {

    /// The four templates that consult `ProtocolCoverageMap` via a
    /// `assumedKitCoverage(...)` helper, kept together because they are the group
    /// that must all receive `context.inheritedTypesByName`. Extracted from
    /// `collectPerSummarySuggestions` on 2026-08-02, when adding the fourth pushed
    /// that function past the 50-line body cap.
    ///
    /// **`BinaryIdempotenceTemplate` is the fourth, and it was missing.** It had no
    /// veto helper and this call site passed it no conformance index, so
    /// `union`/`intersection` on a `SetAlgebra` carrier were proposed unconditionally
    /// against a kit that runs both idempotence laws. Grouping them here makes the
    /// next omission visible: a template in this function that takes no
    /// `inheritedTypesByName` is either deliberate or a double-report waiting to
    /// happen. See `docs/protocol-coverage-law-drift.md`.
    static func collectAlgebraicShapeSuggestions(
        summary: FunctionSummary,
        reducerOps: Set<String>,
        context: CollectionResolverContext,
        generatorType summaryGenType: String?,
        into collector: inout SuggestionCollector
    ) {
        if let suggestion = IdempotenceTemplate.suggest(
            for: summary,
            vocabulary: context.vocabulary,
            inheritedTypesByName: context.inheritedTypesByName,
            carrierKindResolver: context.carrierKindResolver
        ) {
            collector.record(suggestion, generatorType: summaryGenType)
        }
        // The replay counterpart: fires on the key-routed handlers the value
        // template above vetoes. Effect-shaped, not value-shaped — see
        // `ReplayIdempotenceTemplate`.
        if let suggestion = ReplayIdempotenceTemplate.suggest(for: summary) {
            collector.record(suggestion, generatorType: summaryGenType)
        }
        if let suggestion = CommutativityTemplate.suggest(
            for: summary,
            vocabulary: context.vocabulary,
            inheritedTypesByName: context.inheritedTypesByName
        ) {
            collector.record(
                suggestion,
                contradictionTypes: commutativityTypes(for: summary),
                generatorType: summaryGenType
            )
        }
        if let suggestion = AssociativityTemplate.suggest(
            for: summary,
            vocabulary: context.vocabulary,
            reducerOps: reducerOps,
            inheritedTypesByName: context.inheritedTypesByName
        ) {
            collector.record(suggestion, generatorType: summaryGenType)
        }
        // The third semilattice leg: `op(x, x) == x` for a curated join/meet.
        if let suggestion = BinaryIdempotenceTemplate.suggest(
            for: summary,
            inheritedTypesByName: context.inheritedTypesByName
        ) {
            collector.record(suggestion, generatorType: summaryGenType)
        }
    }
}
