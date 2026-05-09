/// V1.13.1 — canonical home for the curated argument-label set used by
/// the three direction-label counter-signals on `IdempotenceTemplate`
/// (V1.10.1), `InversePairTemplate` (V1.11.1), and `RoundTripTemplate`
/// (V1.12.1).
///
/// Hoisted from `IdempotenceTemplate.directionLabels` (where the set
/// landed in V1.10.1 as the first-consumer-by-default) per the v1.11 +
/// v1.12 open-decision-#2 commitments: when round-trip became the third
/// consumer in cycle 9, the cross-template reach to a static let on
/// `IdempotenceTemplate` became the wrong shape. v1.13 (cycle 10)
/// completes the four-cycle abstraction-development cadence: introduce
/// (cycle 7) → replicate (cycle 8) → complete the family (cycle 9) →
/// hoist (cycle 10, this file).
///
/// Companion to `Signal.Kind.directionLabel` (also in `SwiftInferCore`,
/// added in V1.10.1) — the enum case and the curated set now live in
/// the same module, mirroring how every other shared signal kind +
/// curated data pair is factored.
public enum DirectionLabels {

    /// 10-element curated argument-label set indicating directional
    /// (increment/decrement) intent rather than true-inverse / round-
    /// trip / idempotence semantics. Templates emit a per-template
    /// counter-signal weight when *either* side of a pair (or the
    /// single function on idempotence) carries one of these labels as
    /// its first parameter's argument label.
    ///
    /// Consumers (post-v1.13):
    /// - `IdempotenceTemplate` — `-15` weight on `+30` baseline (V1.10.1).
    /// - `InversePairTemplate` — `-10` weight on `+25` baseline (V1.11.1;
    ///   lower weight calibrated for the lower baseline).
    /// - `RoundTripTemplate` — `-15` weight on `+30` baseline (V1.12.1;
    ///   matches idempotence's calibration verbatim).
    ///
    /// Per-template counter-weight calibrates to the template's
    /// typeSymmetry baseline; the curated set itself is template-
    /// agnostic and was validated empirically across `+25` / `+30` /
    /// `+30` baselines in calibration cycles 7-9 (cumulative trajectory
    /// 349 → 257, −26.4% from the three direction-counter mechanisms).
    ///
    /// **Cycle-6 motivation.** The cycle-6 single-runner triage showed
    /// idempotence acceptance at 0/10 = 0% on the post-V1.8.1 surface;
    /// 5 of 10 rejected picks had argument labels in this set
    /// (`index(after:)`, `bucket(after:)`, `index(before:)`). The
    /// corresponding cycle-7 / cycle-8 / cycle-9 measurements
    /// confirmed the set generalizes across templates with no
    /// false-positive collateral observed across nine cycles of corpus
    /// measurement.
    ///
    /// **Closed.** Stride-style labels (`startingAt`, `endingAt`,
    /// `from`, `until`, `offset`) are deliberately *not* in this set;
    /// they're a different label-style class (positional anchors, not
    /// increment/decrement direction) and would be a separate curated
    /// set under cycle-10's stride-style label extension priority. The
    /// 1 Algo `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)`
    /// survivor on round-trip + inverse-pair templates is the test
    /// bed for that future addition.
    public static let curated: Set<String> = [
        "after", "before",
        "next", "prev", "previous",
        "advance", "succ", "pred", "successor", "predecessor"
    ]
}
