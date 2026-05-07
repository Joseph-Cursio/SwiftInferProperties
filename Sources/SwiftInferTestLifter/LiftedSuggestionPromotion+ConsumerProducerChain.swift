import SwiftInferCore

/// M16.2 — consumer-producer chain explainability helper consumed by
/// `LiftedSuggestion.toSuggestion(...)` via `makeExplainability()`.
/// Split out of `LiftedSuggestionPromotion.swift` to keep that file
/// under SwiftLint's 400-line cap.
extension LiftedSuggestion {

    /// M16.2 — explainability for the general consumer-producer chain
    /// advisory finding (PRD §7.8 second example, generalized). Surfaces
    /// the corpus observation (consumer's argument was uniformly the
    /// producer's output across N sites) plus either the suggested
    /// generator or the producer-veto reason. Distinct from M10's
    /// round-trip-pair explainability shape because M16's finding
    /// isn't anchored on a known M5 round-trip pair — only on a
    /// general (consumer, producer) chain that survived the five-fold
    /// narrow scope.
    func consumerProducerChainExplainability(hint: DomainHint) -> ExplainabilityBlock {
        let header = "Consumer-producer chain \(hint.reverseName) ← \(hint.producerName) observed"
            + " across \(hint.siteCount) test sites:"
        let detail = "  • every observed call to \(hint.reverseName)(_:) received"
            + " \(hint.producerName)(_:) output as its argument"
        var why = [header, detail]
        if let veto = hint.producerVeto {
            why.append("Generator narrowing skipped: \(veto.advisoryReason).")
        } else {
            why.append("Suggested narrowed generator: \(hint.suggestedGenerator)")
        }
        let advisoryCaveat = "Advisory only — the chain is documentation that"
            + " \(hint.reverseName)'s tested domain is narrower than its declared"
            + " parameter type. Author a property that exercises \(hint.reverseName)"
            + " against arbitrary \(hint.domainTypeName)s if the broader domain"
            + " is also intended."
        return ExplainabilityBlock(whySuggested: why, whyMightBeWrong: [advisoryCaveat])
    }
}
