import SwiftInferCore

/// V1.15.1 — domain-marker counter-signal extension on
/// `InversePairTemplate`. Defensive scaffold: post-v1.14, OC inverse-
/// pair surface is at 0 (the V1.14.1 SetAlgebra-shape veto cleared the
/// 6 pre-cycle-11 candidates; no domain-marker candidates remain on
/// any of the four cycle-1...11 corpora). The wiring exists for
/// symmetry with `IdempotenceTemplate` + `RoundTripTemplate` and
/// future-proofing: if a future pair like
/// `x.foo(forScale:) ↔ y.bar(forCapacity:)` arises, the same logic
/// suppresses.
///
/// Mechanism class: parameter-label counter (semantic-intent variant).
/// Mirrors V1.11.1's direction-label counter shape; consumes the new
/// V1.15.1 `DomainMarkerLabels.curated` set rather than the V1.13.1
/// `DirectionLabels.curated` set.
///
/// File-split per the V1.6.1 / V1.8.1 / V1.10.1 / V1.11.1 / V1.12.1 /
/// V1.14.1 file-length precedent.
extension InversePairTemplate {

    /// Fires when **both** sides of the pair's first-parameter argument
    /// labels are in `DomainMarkerLabels.curated`.
    ///
    /// **Both-sides detection** matches `RoundTripTemplate`'s V1.15.1
    /// posture per V1.15.0 plan open decision #2 (preserve asymmetric
    /// `forX:` ↔ `for:` candidates as possible true-positives).
    ///
    /// Score arithmetic for inverse-pair (baseline `+25` typeSymmetry):
    /// - bare typeSymmetry (`+25`) `- 15` = `+10` → Suppressed (< 20).
    /// - typeSymmetry + curated/project name (`+10`) `- 15` = `+20`
    ///   → boundary-Possible (the calibration plan's open decision #1
    ///   accepted this margin; curated names like `parse/format` are
    ///   unlikely to coincide with HashTable domain labels in practice).
    /// - typeSymmetry + direction counter (`-10`) `- 15` = `0`
    ///   → Suppressed (the curated domain-marker + direction labels
    ///   would not normally coexist, but the additive score arithmetic
    ///   composes correctly if they did).
    /// - typeSymmetry + SetAlgebra-shape veto (`-25`) `- 15` = `-15`
    ///   → Suppressed (deeper margin; SetAlgebra ops use `_:` labels
    ///   so this composition is hypothetical).
    ///
    /// Weight `-15` (uniform with idempotence + round-trip per V1.15.0
    /// open decision #1).
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
                + "conversions, not an inverse pair"
        )
    }
}
