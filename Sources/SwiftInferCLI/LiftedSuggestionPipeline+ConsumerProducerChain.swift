import SwiftInferCore
import SwiftInferTestLifter

/// M16.2 — consumer-producer chain helpers consumed by
/// `LiftedSuggestionPipeline.promote(...)`. Split out of
/// `LiftedSuggestionPipeline.swift` to keep that file under SwiftLint's
/// 400-line cap. Mirrors the `LiftedSuggestionPipeline+EquivalenceClass.swift`
/// posture for M11/M13.
extension LiftedSuggestionPipeline {

    /// M16.2 — runs `ConsumerProducerChainDetector.detect(...)` against
    /// the corpus-wide call-site map and emits one `LiftedSuggestion`
    /// per qualifying chain. Synthetic `LiftedOrigin` keys on the
    /// consumer name (the chain is a corpus-level finding; no single
    /// test method is canonical), mirroring `equivalenceClassLifted(
    /// ...)`'s posture.
    static func consumerProducerChainLifted(
        from callSitesByConsumer: [String: [DomainCallSite]],
        roundTripPairs: [RoundTripPair],
        summariesByName: [String: FunctionSummary]
    ) -> [LiftedSuggestion] {
        guard !callSitesByConsumer.isEmpty else { return [] }
        let hints = ConsumerProducerChainDetector.detect(
            callSitesByConsumer: callSitesByConsumer,
            summariesByName: summariesByName,
            knownRoundTripPairs: roundTripPairs
        )
        return hints.map { hint in
            let originLocation = summariesByName[hint.reverseName]?.location
                ?? SourceLocation(file: "<corpus>", line: 0, column: 0)
            let origin = LiftedOrigin(
                testMethodName: "consumer-producer-chain:\(hint.reverseName)",
                sourceLocation: originLocation
            )
            return LiftedSuggestion.consumerProducerChain(hint: hint, origin: origin)
        }
    }

    /// M16.3 — runs `ConsumerProducerChainDetector.detect(...)` and
    /// returns the per-promoted-suggestion-identity hint map the
    /// `InteractiveTriage.Context` carries to the accept-flow
    /// renderer. Identity matches `LiftedSuggestion.consumerProducerChain`'s
    /// `makeIdentity()` shape so the lookup hits exactly the post-
    /// promotion suggestion's `identity`. Mirrors
    /// `equivalenceClassHintMap(from:summaries:typeDecls:)` posture.
    public static func consumerProducerChainHintMap(
        from callSitesByConsumer: [String: [DomainCallSite]],
        roundTripPairs: [RoundTripPair],
        summaries: [FunctionSummary]
    ) -> [SuggestionIdentity: DomainHint] {
        let summariesByName = LiftedSuggestionRecovery.summariesByName(summaries)
        let hints = ConsumerProducerChainDetector.detect(
            callSitesByConsumer: callSitesByConsumer,
            summariesByName: summariesByName,
            knownRoundTripPairs: roundTripPairs
        )
        var map: [SuggestionIdentity: DomainHint] = [:]
        for hint in hints {
            // Mirrors `LiftedSuggestion.consumerProducerChain` ->
            // `makeIdentity` which sorts the calleeNames pair lexically.
            let calleeNames = [hint.producerName, hint.reverseName].sorted()
            let identity = SuggestionIdentity(
                canonicalInput: "lifted|consumer-producer-chain|\(calleeNames.joined(separator: ","))"
            )
            map[identity] = hint
        }
        return map
    }

    /// M16.3 — derive the M5 round-trip pair set from lifted
    /// suggestions for use as the consumer-producer-chain detector's
    /// anti-double-fire input.
    public static func roundTripPairs(
        from lifted: [LiftedSuggestion]
    ) -> [RoundTripPair] {
        lifted.compactMap { suggestion in
            guard case .roundTrip(let detection) = suggestion.pattern else {
                return nil
            }
            return RoundTripPair(
                forwardName: detection.forwardCallee,
                reverseName: detection.backwardCallee,
                domainTypeName: ""
            )
        }
    }
}
