import SwiftInferCore

/// Stream-consumption veto on `IdempotenceTemplate.suggest(forLifted:)` —
/// closes the `swift-syntax` parsing-survey finding
/// (`docs/parsing-catalog-gap.md` §2): 53 of `SwiftParser`'s 98 default-tier
/// suggestions were lifted idempotence at `Likely` on cursor-consuming methods,
/// and all 53 are false.
///
/// Fires `Signal.vetoWeight` when `StreamConsumption.verdict` matches either
/// tier — a consuming verb on any carrier, or any non-restoring `mutating`
/// method on a stream-position carrier. See `StreamConsumption` for why the
/// second tier is the broad one and why the match is camelCase-token-exact.
///
/// **Relation to the three sibling vetoes.**
/// - `iteratorProtocolCarrierVeto` (V1.21.A) — same argument, gated on
///   `IteratorProtocol` / `Sequence` conformance. This veto is the
///   conformance-free generalization, so the two are **chained** in
///   `liftedCarrierVetoes` (`else if`), not stacked: a carrier that satisfies
///   both renders one veto bullet, not two.
/// - `mutatorBlocklistVeto` (V1.24.B) — curated *collection* consumers
///   (`removeFirst`, `pop`, `dropFirst`). This one covers the *stream*
///   consumers. Disjoint name sets; both may fire, as they may today.
/// - `nonDeterministicMutatorVeto` (V1.24.C) — orthogonal (`shuffle`).
///
/// **Known residue, recorded rather than papered over.** One of the 53,
/// `RegexLiteralLexemes.Builder.recordOpenSlash()`, is not caught: `record` is
/// not a consuming verb and `Builder` is deliberately not a stream noun. It is
/// non-idempotent for a different reason — it *appends* — which is the
/// accumulator family, and claiming it here would make this veto's stated
/// rationale false about one of its own firings.
extension IdempotenceTemplate {

    /// Returns a veto `Signal` (weight `Signal.vetoWeight`) when the lifted
    /// candidate is a stream consumption. `nil` otherwise.
    ///
    /// Wired into `IdempotenceTemplate.suggest(forLifted:)` via
    /// `liftedCarrierVetoes(...)`.
    static func streamConsumptionVeto(
        forLifted lifted: LiftedTransformation
    ) -> Signal? {
        let methodName = lifted.originalSummary.name
        let carrier = ProtocolCoverageMap.strippingGenericParameters(lifted.carrier)
        guard let reason = StreamConsumption.verdict(
            methodName: methodName,
            carrier: carrier
        ) else {
            return nil
        }
        return Signal(
            kind: .protocolCoveredProperty,
            weight: Signal.vetoWeight,
            detail: "Stream consumption: \(reason) — a position in a stream "
                + "moves on every call, so `\(methodName)()` applied twice is "
                + "not `\(methodName)()` applied once; the lifted shadow "
                + "`(\(lifted.carrier)) -> \(lifted.carrier)` is not idempotent. "
                + "The law this function does owe is monotone progress "
                + "(the position advances or stops, never retreats)"
        )
    }
}
