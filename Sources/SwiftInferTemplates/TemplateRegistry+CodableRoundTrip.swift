import SwiftInferCore

extension TemplateRegistry {

    /// codable-round-trip fan-out — a type-level pass (needs both `typeDecls`
    /// and `summaries`) that pairs a custom `encode(to:)` with a custom
    /// `init(from:)` on the same type. Synthesized `Codable` emits no source
    /// declarations, so this only ever fires on hand-written conformances (the
    /// automatic custom-conformance gate; see `CodableRoundTripTemplate`).
    static func collectCodableRoundTripSuggestions(
        summaries: [FunctionSummary],
        typeDecls: [TypeDecl],
        into collector: inout SuggestionCollector
    ) {
        for suggestion in CodableRoundTripTemplate.suggestions(
            typeDecls: typeDecls,
            summaries: summaries
        ) {
            collector.record(suggestion, generatorType: suggestion.carrier)
        }
    }
}
