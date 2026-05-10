import SwiftInferCore

/// V1.22.D — stride-style label veto on `InversePairTemplate`. Companion
/// to `RoundTripTemplate+StrideStyleVeto.swift`; same curated set + same
/// firing rule (both pair sides stride-style-labeled), same -25 weight,
/// same cycle-14-demotion rationale.
///
/// Inverse-pair on the Algo `endOfChunk × startOfChunk` site fires
/// because both halves have non-Equatable `Base.Index` carriers (the
/// V1.5.2 EquatableResolver returns `.notEquatable` or `.unknown`).
/// V1.22.D suppresses inverse-pair claims on stride-style pair sites.
extension InversePairTemplate {

    /// Returns a `-25` veto signal when both pair sides have first-
    /// parameter labels in `StrideStyleLabels.curated`. `nil` otherwise.
    ///
    /// Wired into `InversePairTemplate.counterAndCoverageSignals(for:)`
    /// alongside `directionLabelCounterSignal`, `domainMarkerCounterSignal`,
    /// `setAlgebraShapeVeto`.
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
                + "bounded sequence iteration, not a functional-inverse pair; "
                + "cycle-14 demotion target"
        )
    }
}
