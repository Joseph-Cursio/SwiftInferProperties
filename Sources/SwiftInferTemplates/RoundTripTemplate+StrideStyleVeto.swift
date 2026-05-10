import SwiftInferCore

/// V1.22.D — stride-style label veto on `RoundTripTemplate`. Closes
/// the cycle-14-demoted Algo `endOfChunk(startingAt:) × startOfChunk(endingAt:)`
/// round-trip pick (cycle-14 priority #1 → demoted to v1.18 → not
/// shipped in cycles 15-18 → shipped here in v1.22).
///
/// Fires `-25` (full veto magnitude) when **both** pair sides have
/// first-parameter labels in `StrideStyleLabels.curated`. Mirrors
/// V1.22.B's both-sides direction-counter posture exactly: only the
/// truly-symmetric stride-style pairs get suppressed; asymmetric pairs
/// (one side stride-labeled, one not) preserve at no-fire.
///
/// **Why both-sides only:** asymmetric stride-style pairs (e.g.,
/// `endOfChunk(startingAt:) × _someOtherFunction(_:)`) are likely cross-
/// product noise that other counters (cross-type, domain-marker, math-
/// forward) already handle. Only the matched bookend pairs are the
/// V1.22.D target — they survived all prior cycles' counters by being
/// shape-symmetric AND name-correlated.
///
/// Mechanism class: extends class 6 (parameter-label semantic-intent
/// counter, V1.10.1 / V1.12.1 / V1.15.1 / V1.22.B lineage) with a new
/// curated set `StrideStyleLabels.curated`. Same shape as V1.12.1's
/// direction-counter; different curated content.
extension RoundTripTemplate {

    /// Returns a `-25` veto signal when both pair sides have first-
    /// parameter labels in `StrideStyleLabels.curated`. `nil` otherwise.
    ///
    /// Wired into `RoundTripTemplate.suggest(for:)` alongside the
    /// existing `directionLabelCounterSignal`, `setAlgebraShapeVeto`,
    /// `mathForwardFunctionPairVeto` calls.
    static func strideStyleLabelCounterSignal(for pair: FunctionPair) -> Signal? {
        guard let forwardLabel = pair.forward.parameters.first?.label,
              let reverseLabel = pair.reverse.parameters.first?.label,
              StrideStyleLabels.curated.contains(forwardLabel),
              StrideStyleLabels.curated.contains(reverseLabel) else {
            return nil
        }
        return Signal(
            kind: .directionLabel,
            weight: -25,
            detail: "Both pair sides stride-style-labeled "
                + "('\(forwardLabel)' / '\(reverseLabel)') — paired range-"
                + "bounded sequence iteration, not a round-trip codec; "
                + "cycle-14 demotion target (correctness-positive but "
                + "auto-emit usability blocker)"
        )
    }
}
