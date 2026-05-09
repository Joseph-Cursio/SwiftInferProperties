import SwiftInferCore

/// V1.15.1 — domain-marker counter-signal extension on
/// `RoundTripTemplate`. Closes post-v1.14 priority #1 from
/// `docs/calibration-cycle-11-findings.md` (OC HashTable internals: 9
/// round-trip Possible-tier survivors with both pair sides' first-
/// parameter labels in `DomainMarkerLabels.curated`).
///
/// Mechanism class: parameter-label counter (semantic-intent variant).
/// Mirrors V1.12.1's direction-label counter shape; consumes the new
/// V1.15.1 `DomainMarkerLabels.curated` set rather than the V1.13.1
/// `DirectionLabels.curated` set.
///
/// File-split per the V1.6.1 / V1.8.1 / V1.10.1 / V1.11.1 / V1.12.1 /
/// V1.14.1 file-length precedent.
extension RoundTripTemplate {

    /// Fires when **both** sides of the pair's first-parameter argument
    /// labels are in `DomainMarkerLabels.curated` (e.g.,
    /// `minimumCapacity(forScale:) ↔ maximumCapacity(forScale:)`,
    /// `minimumCapacity(forScale:) ↔ scale(forCapacity:)`).
    ///
    /// **Both-sides detection** (vs V1.10.1 / V1.11.1 / V1.12.1's
    /// either-side detection on `DirectionLabels`). Per V1.15.0 plan
    /// open decision #2: preserves the asymmetric OC candidate
    /// `_value(forBucketContents:) ↔ _bucketContents(for:)` which is
    /// likely a true-positive round-trip pair. The semantic argument
    /// "both sides explicitly mark named domains in their parameter
    /// labels = cross-domain chain, not round-trip" requires both
    /// sides to be labeled. Asymmetric labeling (`forX:` ↔ `for:`)
    /// often signals a real round-trip where one side is the
    /// "structured input → carrier" direction and the other is the
    /// "carrier → structured output" direction.
    ///
    /// Score arithmetic for round-trip (baseline `+30` typeSymmetry):
    /// - bare typeSymmetry (`+30`) `- 15` = `+15` → Suppressed (< 20).
    /// - typeSymmetry + curated `encode/decode` (`+40`) `- 15` = `+55`
    ///   → Likely (preserves curated name signal — well above `+40`).
    /// - typeSymmetry + `@Discoverable(group:)` (`+35`) `- 15` = `+50`
    ///   → Likely (preserves explicit user signal).
    /// - typeSymmetry + cross-type counter (`-25`) `- 15` = `-10`
    ///   → Suppressed (deeper margin via additive composition).
    ///
    /// Weight `-15` (matches V1.10.1 / V1.12.1).
    ///
    /// **Cycle-11 motivation.** The cycle-11 post-SetAlgebra-veto
    /// snapshot showed 9 OC round-trip Possible-tier survivors with
    /// both-sides domain-marker labels (the 6 unprefixed HashTable
    /// capacity/scale-conversion pairs plus 3 underscore-prefixed
    /// variants), all `Int -> Int ↔ Int -> Int` shapes that pass
    /// typeSymmetry but cross domains semantically.
    static func domainMarkerCounterSignal(
        for pair: FunctionPair
    ) -> Signal? {
        guard let forwardLabel = pair.forward.parameters.first?.label,
              let reverseLabel = pair.reverse.parameters.first?.label,
              DomainMarkerLabels.curated.contains(forwardLabel),
              DomainMarkerLabels.curated.contains(reverseLabel) else {
            return nil
        }
        return Signal(
            kind: .directionLabel,
            weight: -15,
            detail: "Domain-marker labels: '\(forwardLabel)' ↔ "
                + "'\(reverseLabel)' — both sides are cross-domain "
                + "conversions, not a round-trip pair"
        )
    }
}
