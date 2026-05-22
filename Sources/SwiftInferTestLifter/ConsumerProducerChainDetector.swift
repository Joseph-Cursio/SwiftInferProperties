import SwiftInferCore

/// TestLifter M16.1 — pure-function pass that surfaces general
/// consumer-producer chains from the corpus-wide call-site map.
///
/// **Generalizes M10's narrow round-trip-pair surface.** Where
/// `DomainInferrer` emits a `DomainHint` only when the consumer is the
/// reverse side of a known M5 round-trip pair, this detector lifts that
/// filter and emits a comment-only advisory hint for any (consumer,
/// producer) chain meeting the five-fold narrow-scope criterion below
/// (PRD §7.8 second example, generalized).
///
/// Inputs:
/// - `callSitesByConsumer`: corpus-wide `[String: [DomainCallSite]]`
///   from `DomainCorpusScanner.mergeCallSites(...)`. Each site's
///   `argument` classification has already been resolved against its
///   originating slice's setup bindings (per
///   `DomainCorpusScanner.artifacts(in:)`); identifier sites that
///   didn't resolve degrade to `.other` and become outliers per PRD §3.5.
/// - `summariesByName`: name → first-match `FunctionSummary` index.
///   The detector consults this for both the producer (existence +
///   throws / async / multi-arg veto) and the consumer (first-arg type
///   for the type-alignment criterion).
/// - `knownRoundTripPairs`: M5 round-trip detector's surviving pairs.
///   Used for anti-double-fire — when an M5 pair `(forward: P,
///   reverse: consumer)` exists, M10 owns the surface; M16 stays out
///   of its lane.
/// - `producerArgGeneratable`: predicate over a producer's arg-type
///   name. Decoupled into a parameter (mirrors `DomainInferrer.infer(
///   ...)`'s posture) so unit tests can exercise the veto without
///   wiring the full M3+ `DerivationStrategist` strategy table. The
///   pipeline caller currently passes `{ _ in true }` per the same
///   deferred-veto posture as M10's pipeline arm (M10 plan OD #4).
///
/// Returns one `DomainHint` per qualifying chain (with
/// `origin == .consumerProducerChain`). Empty when no chains qualify.
///
/// **Hard contract (PRD §15):** never throws. Empty input maps return
/// an empty result.
public enum ConsumerProducerChainDetector {

    /// The five-criterion narrow scope from the M16 plan (§"Scope-
    /// narrowing decision"):
    ///
    /// 1. **Threshold:** `sites.count >= 3` (M4.3 / M9 / M10).
    /// 2. **Homogeneity:** every site classifies as
    ///    `.callOutput(producerName: P)` for the same `P`. One outlier
    ///    kills (PRD §3.5).
    /// 3. **Producer-existence:** `summariesByName[P] != nil`. Stdlib
    ///    initializers (`String("hello")`, `Int(s)`) and unknown
    ///    identifiers fail this check.
    /// 4. **Type-alignment:** `producerSummary.returnTypeText` matches
    ///    the consumer's first-parameter `typeText`. The consumer must
    ///    also be a known summary so we have its first-parameter type.
    /// 5. **Anti-double-fire:** no M5 round-trip pair `(forwardName: P,
    ///    reverseName: consumer)` exists. M10 owns the round-trip case;
    ///    M16 stays out of its lane.
    public static func detect(
        callSitesByConsumer: [String: [DomainCallSite]],
        summariesByName: [String: FunctionSummary],
        knownRoundTripPairs: [RoundTripPair],
        producerArgGeneratable: (String) -> Bool = { _ in true }
    ) -> [DomainHint] {
        guard !callSitesByConsumer.isEmpty else {
            return []
        }
        let roundTripIndex = roundTripPairIndex(knownRoundTripPairs)
        // Sort consumer keys so output is deterministic — callers
        // (pipeline + tests) treat the result as a flat list.
        let sortedConsumers = callSitesByConsumer.keys.sorted()
        var hints: [DomainHint] = []
        for consumer in sortedConsumers {
            guard let sites = callSitesByConsumer[consumer] else { continue }
            if let hint = chainHint(
                consumer: consumer,
                sites: sites,
                summariesByName: summariesByName,
                roundTripIndex: roundTripIndex,
                producerArgGeneratable: producerArgGeneratable
            ) {
                hints.append(hint)
            }
        }
        return hints
    }

    private static func chainHint(
        consumer: String,
        sites: [DomainCallSite],
        summariesByName: [String: FunctionSummary],
        roundTripIndex: Set<RoundTripPairKey>,
        producerArgGeneratable: (String) -> Bool
    ) -> DomainHint? {
        guard sites.count >= 3 else { return nil }
        guard let producerName = homogeneousProducer(in: sites) else { return nil }
        guard let producerSummary = summariesByName[producerName] else { return nil }
        guard let consumerArgType = consumerFirstArgType(
            consumer: consumer,
            summariesByName: summariesByName
        ) else { return nil }
        guard producerSummary.returnTypeText == consumerArgType else { return nil }
        guard !roundTripIndex.contains(
            RoundTripPairKey(forwardName: producerName, reverseName: consumer)
        ) else { return nil }
        let veto = DomainInferrer.computeVeto(
            forwardSummary: producerSummary,
            producerArgGeneratable: producerArgGeneratable(consumerArgType)
        )
        return DomainHint(
            forwardName: producerName,
            reverseName: consumer,
            producerName: producerName,
            domainTypeName: consumerArgType,
            siteCount: sites.count,
            producerVeto: veto,
            suggestedGenerator: "Gen<\(consumerArgType)>.map(\(producerName))",
            origin: .consumerProducerChain
        )
    }

    /// Returns the single producer name when every site's classification
    /// is `.callOutput(producerName:)` for the same `P`. Returns `nil`
    /// when any site is `.identifier` (unresolved), `.other`, or a
    /// `.callOutput` for a different producer.
    private static func homogeneousProducer(in sites: [DomainCallSite]) -> String? {
        var observed: String?
        for site in sites {
            switch site.argument {
            case .callOutput(let producerName):
                if let already = observed, already != producerName {
                    return nil
                }
                observed = producerName

            case .identifier, .other:
                return nil
            }
        }
        return observed
    }

    /// Recover the consumer's first explicit-parameter type for the
    /// type-alignment check. Mirrors how the corpus scanner's
    /// `firstArg` recording lines up with `parameters[0]` for both
    /// free functions and instance methods (the corpus scanner records
    /// the first explicit positional argument inside parens; for an
    /// instance-method call `a.validate(b)` that's `b`, which lines up
    /// with the method's `parameters[0]`). Returns `nil` when the
    /// consumer is unknown or has no explicit parameters (which would
    /// mean the corpus's `argument` was `.other` and homogeneity
    /// already killed the chain).
    private static func consumerFirstArgType(
        consumer: String,
        summariesByName: [String: FunctionSummary]
    ) -> String? {
        guard let summary = summariesByName[consumer] else { return nil }
        return summary.parameters.first?.typeText
    }

    /// Set-shaped index over the M5 round-trip pairs so anti-double-
    /// fire is an O(1) lookup per qualifying chain.
    private static func roundTripPairIndex(
        _ pairs: [RoundTripPair]
    ) -> Set<RoundTripPairKey> {
        Set(pairs.map { RoundTripPairKey(forwardName: $0.forwardName, reverseName: $0.reverseName) })
    }

    private struct RoundTripPairKey: Hashable {
        let forwardName: String
        let reverseName: String
    }
}
