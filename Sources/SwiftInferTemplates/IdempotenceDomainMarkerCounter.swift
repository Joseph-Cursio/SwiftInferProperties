import SwiftInferCore

/// V1.15.1 — domain-marker counter-signal extension on
/// `IdempotenceTemplate`. Closes post-v1.14 priority #1 from
/// `docs/calibration-cycle-11-findings.md` (OC HashTable internals: 7
/// idempotence Possible-tier survivors with first-parameter labels in
/// `DomainMarkerLabels.curated`).
///
/// Mechanism class: parameter-label counter (semantic-intent variant)
/// — extends the cycles 7-9 direction-label family. Distinct from
/// V1.10.1's spatial-sequence direction-label counter by intent:
/// domain markers describe *named domains* (scale, capacity, bucket-
/// contents), not *positions in an ordered sequence*.
///
/// File-split per the V1.6.1 / V1.8.1 / V1.10.1 / V1.11.1 / V1.12.1 /
/// V1.14.1 file-length precedent — keeps each calibration mechanism
/// in a self-contained file for attribution clarity. Idempotence's
/// V1.10.1 direction-label counter lives inline in
/// `IdempotenceTemplate.swift`; v1.15 introduces the file-split
/// posture for idempotence consistent with the inverse-pair / round-
/// trip pattern.
extension IdempotenceTemplate {

    /// Fires when the candidate's first-parameter argument label is in
    /// `DomainMarkerLabels.curated` (e.g.,
    /// `minimumCapacity(forScale:)`, `scale(forCapacity:)`,
    /// `_value(forBucketContents:)`).
    ///
    /// Score arithmetic for idempotence (baseline `+30` typeSymmetry):
    /// - bare typeSymmetry (`+30`) `- 15` = `+15` → Suppressed (< 20).
    /// - typeSymmetry + curated/project verb (`+40`) `- 15` = `+55`
    ///   → Likely (preserves explicit verb signal; curated verbs like
    ///   `normalize` / `trim` are unlikely to coincide with HashTable
    ///   domain labels but the override exists by symmetry with V1.10.1).
    ///
    /// Weight `-15` (mirrors V1.10.1 idempotence verbatim).
    /// Conservative-precision posture (PRD §3.5) prefers the cleaner-
    /// margin option; `-15` lands bare-shape pairs at `+15` Suppressed
    /// with a clean 5-point margin from the `+20` boundary.
    ///
    /// **Cycle-11 motivation.** The cycle-11 post-SetAlgebra-veto
    /// snapshot showed 7 OC idempotence Possible-tier survivors with
    /// domain-marker labels: 4 unprefixed (`minimumCapacity(forScale:)`,
    /// `maximumCapacity(forScale:)`, `scale(forCapacity:)`,
    /// `wordCount(forScale:)`) + 3 underscore-prefixed
    /// (`_minimumCapacity(forScale:)`, `_maximumCapacity(forScale:)`,
    /// `_scale(forCapacity:)`). Applying any of these twice means
    /// feeding capacity-domain output into a scale-domain input slot,
    /// which is structurally wrong even though the type is `Int -> Int`.
    static func domainMarkerCounterSignal(
        for summary: FunctionSummary
    ) -> Signal? {
        guard let label = summary.parameters.first?.label,
              DomainMarkerLabels.curated.contains(label) else {
            return nil
        }
        return Signal(
            kind: .directionLabel,
            weight: -15,
            detail: "Domain-marker label: '\(label)' — function is "
                + "likely a cross-domain conversion (named-domain input) "
                + "rather than idempotent"
        )
    }
}
