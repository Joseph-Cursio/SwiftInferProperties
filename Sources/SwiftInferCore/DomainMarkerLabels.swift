/// V1.15.1 — canonical home for the curated semantic-intent argument-
/// label set used by the three domain-marker counter-signals on
/// `IdempotenceTemplate`, `InversePairTemplate`, and `RoundTripTemplate`
/// (cycle 12; first cycle to ship a single mechanism applied to three
/// templates simultaneously).
///
/// **Canonical from cycle 1.** Lives in `SwiftInferCore` from V1.15.1
/// without a per-template intermediate, applying the v1.13 hoist lesson
/// preemptively (mirrors V1.14.1's `SetAlgebraShape` factoring posture).
///
/// Companion to `DirectionLabels.curated` (V1.13.1) and
/// `SetAlgebraShape.binaryOps` (V1.14.1) — the three are the canonical
/// homes for cycle-N curated data sets used across templates. All
/// factored as `public enum <Name> { public static let <subset>:
/// Set<String> }`.
///
/// **Mechanism class.** Parameter-label counter (semantic-intent
/// variant) — extends the cycles 7-9 direction-label family with non-
/// directional curated labels for cross-domain conversions. Distinct
/// from `DirectionLabels.curated`'s spatial-sequence labels by intent:
/// domain markers describe *named domains* (scale, capacity, bucket-
/// contents), not *positions in an ordered sequence*.
public enum DomainMarkerLabels {

    /// 3-element curated set of semantic-intent argument labels that
    /// indicate cross-domain conversion rather than round-trip /
    /// idempotence / inverse-pair semantics. Templates emit a per-
    /// template counter-signal weight when *either* side of a pair (or
    /// the single function on idempotence) carries one of these labels
    /// as its first parameter's argument label.
    ///
    /// Consumers (post-v1.15):
    /// - `IdempotenceTemplate` — `-15` weight on `+30` baseline.
    /// - `InversePairTemplate` — `-15` weight on `+25` baseline.
    /// - `RoundTripTemplate` — `-15` weight on `+30` baseline.
    ///
    /// Uniform `-15` weight across all three templates per V1.15.0 plan
    /// open decision #1: minimizes per-template surprise; matches the
    /// most-replicated weight in the calibration trajectory; the -10
    /// difference for inverse-pair's `+25` baseline still produces a
    /// clean Suppressed margin.
    ///
    /// **Cycle-11 motivation.** The cycle-11 post-SetAlgebra-veto
    /// snapshot showed OC HashTable internals as the dominant remaining
    /// noise pattern: 12 round-trip + 7 idempotence Possible-tier
    /// survivors with first-parameter labels in this curated set. These
    /// are functions that map between three logically distinct domains
    /// — scale, capacity, and wordCount/bucketContents — even though
    /// the carrier type is `Int -> Int` on every signature.
    ///
    /// **Initial scope: 3 elements.** Per V1.15.0 plan open decision
    /// #3 (witnessed-only): start with the 3 labels witnessed in cycle-
    /// 11 OC survivors (`forScale`, `forCapacity`, `forBucketContents`);
    /// avoid speculative broadening (`forSlot`, `forIndex`, `forBucket`,
    /// `forKey`, `forValue`, `forIdentifier`, etc.) without empirical
    /// justification. Cycle-13+ extends as new corpora surface
    /// candidates.
    ///
    /// Distinct from `DirectionLabels.curated` (positional iteration:
    /// `after` / `before` / `next` / etc.) — domain markers are named-
    /// domain markers, not sequence-position labels. The two sets are
    /// disjoint by intent and don't overlap textually.
    public static let curated: Set<String> = [
        "forScale",
        "forCapacity",
        "forBucketContents"
    ]
}
