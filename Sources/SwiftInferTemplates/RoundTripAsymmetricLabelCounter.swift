import SwiftInferCore

/// V1.24.A — asymmetric label class mismatch counter on
/// `RoundTripTemplate`. Cycle-19 finding + cycle-20 reconfirmed at
/// 5/5 = 100% reject on the OC `index(after:) × _minimumCapacity(forScale:)`-
/// shape pairs.
///
/// Fires `-25` (full veto magnitude) when the pair has **asymmetric
/// label class mismatch**: forward side has a first-parameter label in
/// `DirectionLabels.curated` and reverse side has a first-parameter
/// label in `DomainMarkerLabels.curated`, or vice versa. These are
/// cross-product noise — index-advance functions paired with capacity-
/// from-scale functions share `(Int) -> Int` shape but operate on
/// entirely unrelated domains.
///
/// **Why both-sides asymmetric specifically:**
/// - V1.12.1 fires at -15 when **either** side is direction-labeled.
/// - V1.22.B fires at -25 when **both** sides are direction-labeled.
/// - V1.15.1 fires at -15 when **both** sides are domain-marker-labeled.
/// - V1.24.A closes the missing case: forward direction-labeled +
///   reverse domain-marker-labeled (or mirror).
///
/// Score arithmetic at v1.24:
/// - bare typeSymmetry (+30) + carrier (+5) - 15 (V1.12.1 single-side
///   direction) - 25 (V1.24.A asymmetric) = -5 → Suppressed (clean margin).
///
/// Mechanism class: extension of class 6 (parameter-label semantic-
/// intent counter, V1.10.1/V1.12.1/V1.15.1/V1.22.B lineage) with a new
/// sub-class — asymmetric label class mismatch. Mirrors V1.22.B's
/// both-sides-direction pattern but on a different shape.
extension RoundTripTemplate {

    /// Returns a `-25` counter signal when the pair has asymmetric label
    /// class mismatch (one side direction-labeled, one side domain-
    /// marker-labeled). `nil` otherwise.
    ///
    /// Wired into `RoundTripTemplate.suggest(for:)` alongside the existing
    /// `directionLabelCounterSignal` (V1.12.1/V1.22.B), `domainMarkerCounterSignal`
    /// (V1.15.1), `setAlgebraShapeVeto` (V1.16.1), `mathForwardFunctionPairVeto`
    /// (V1.21.C), `strideStyleLabelCounterSignal` (V1.22.D) calls.
    static func asymmetricLabelClassMismatchCounterSignal(
        for pair: FunctionPair
    ) -> Signal? {
        guard let forwardLabel = pair.forward.parameters.first?.label,
              let reverseLabel = pair.reverse.parameters.first?.label else {
            return nil
        }
        let forwardIsDirection = DirectionLabels.curated.contains(forwardLabel)
        let reverseIsDirection = DirectionLabels.curated.contains(reverseLabel)
        let forwardIsDomain = DomainMarkerLabels.curated.contains(forwardLabel)
        let reverseIsDomain = DomainMarkerLabels.curated.contains(reverseLabel)
        // Asymmetric: exactly one side direction + exactly one side
        // domain-marker. Order-insensitive.
        let directionAndDomain = (forwardIsDirection && reverseIsDomain)
            || (forwardIsDomain && reverseIsDirection)
        guard directionAndDomain else {
            return nil
        }
        return Signal(
            kind: .directionLabel,
            weight: -25,
            detail: "Asymmetric label class mismatch — '\(forwardLabel)' "
                + "(\(forwardIsDirection ? "direction" : "domain-marker")) "
                + "× '\(reverseLabel)' "
                + "(\(reverseIsDirection ? "direction" : "domain-marker")); "
                + "cross-product noise — index-advance × capacity-from-scale "
                + "(or similar) share (Int) -> Int shape but unrelated domains"
        )
    }
}
