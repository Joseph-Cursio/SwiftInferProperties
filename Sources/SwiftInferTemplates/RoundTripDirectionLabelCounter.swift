import SwiftInferCore

/// V1.12.1 — direction-label counter-signal extension on
/// `RoundTripTemplate`. Closes cycle-9 priority #1 from
/// `docs/calibration-cycle-8-findings.md` (round-trip template
/// direction-label counter — third consumer of `Signal.Kind.directionLabel`
/// + `DirectionLabels.curated`). Mirrors v1.10's `IdempotenceTemplate`
/// direction-label counter at the same `-15` weight because round-trip's
/// `+30` typeSymmetry baseline matches idempotence's (not inverse-pair's
/// `+25`, which justified v1.11's `-10`).
///
/// File-split per the V1.6.1 / V1.8.1 / V1.10.1 / V1.11.1 file-length
/// precedent: `RoundTripTemplate.swift` was 348 lines (332-line enum
/// body, well over swiftlint's `type_body_length: 250` warning and
/// within 17 lines of the 350 hard error). Inlining would breach.
///
/// **V1.13.1.** Updated to consume `SwiftInferCore.DirectionLabels.curated`
/// (hoisted from `IdempotenceTemplate.directionLabels` once round-trip
/// became the third consumer in cycle 9 — this very template's
/// landing was what triggered the hoist).
extension RoundTripTemplate {

    /// Fires when *either* side of the pair's first-parameter argument
    /// label is in `DirectionLabels.curated` (e.g.,
    /// `index(after:) ↔ index(before:)`,
    /// `bucket(after:) ↔ bucket(before:)`,
    /// `transform(_:) ↔ untransform(after:)` — the asymmetric case).
    ///
    /// Either-side detection (vs forward-only): asymmetric labeling
    /// like `transform(_:) × untransform(after:)` would be missed by
    /// a forward-only check. Either-side has no false-positive cost
    /// at the `-15` weight because curated/project name matches
    /// preserve Likely tier (`+30 + 40 − 15 = +55`) — well clear of
    /// the `+40` Likely / `+20` Possible boundaries.
    ///
    /// Score arithmetic for round-trip (baseline `+30` typeSymmetry,
    /// matching idempotence):
    /// - bare typeSymmetry (`+30`) `− 15` = `+15` → Suppressed (< 20).
    /// - typeSymmetry + curated/project name (`+40`) `− 15` = `+55`
    ///   → Likely (clean preservation, well above the `+40` boundary).
    /// - typeSymmetry + `@Discoverable(group:)` (`+35`) `− 15` = `+50`
    ///   → Likely (preserved).
    /// - typeSymmetry + cross-type counter (`-25`) `− 15` = `-10`
    ///   → Suppressed (deeper margin; both counters compose correctly).
    ///
    /// Weight `-15` (mirrors v1.10 idempotence verbatim — round-trip's
    /// baseline matches idempotence's `+30`, not inverse-pair's `+25`).
    /// Conservative-precision posture (PRD §3.5) prefers the cleaner-
    /// margin option; `-15` lands bare-shape pairs at `+15` Suppressed
    /// with a clean 5-point margin from the `+20` boundary, while
    /// `-10` would sit exactly on the boundary at `+20`.
    ///
    /// **Cycle-8 motivation.** The cycle-8 post-inverse-direction-
    /// counter snapshot showed round-trip as the largest-surface
    /// template at 181 of 288 = 62.8% of post-v1.11 surface; per-
    /// suggestion line-count survey (rigorous methodology per cycle-8
    /// findings) projected 31 of 181 = 17.1% direction-label fire rate
    /// across the four corpora — Algorithms 18 of 20 (90.0%),
    /// OrderedCollections 13 of 25 (52.0%), ComplexModule 0 of 136
    /// (no direction labels — Complex's binary ops use `_:` parameter
    /// labels), PropertyLawKit 0 of 0.
    static func directionLabelCounterSignal(
        for pair: FunctionPair
    ) -> Signal? {
        let forwardLabel = pair.forward.parameters.first?.label
        let reverseLabel = pair.reverse.parameters.first?.label
        let forwardIsDirectional = forwardLabel.map { DirectionLabels.curated.contains($0) } ?? false
        let reverseIsDirectional = reverseLabel.map { DirectionLabels.curated.contains($0) } ?? false
        guard forwardIsDirectional || reverseIsDirectional else {
            return nil
        }
        // V1.22.B — both-sides direction-labeled bumps to -25 (full veto
        // magnitude). Direct cycle-18 finding closure: 17 OC round-trip
        // survivors at v1.21 are mostly `index(after:) × index(before:)`
        // cross-cell directional pairs; cycle-9 V1.12.1 -15 left them at
        // +30 + 5 (carrier) - 15 = +20 (right at Possible boundary, lifted
        // above visibility by V1.18.A carrier-kind +5). The -25 magnitude
        // sends both-sides-directional pairs to +15 → Suppressed with a
        // clean 5-point margin.
        if forwardIsDirectional, reverseIsDirectional {
            // Both labels in the curated set — render both for clarity.
            // Force-unwrapped because the boolean guards above already
            // confirmed both labels exist + match the curated set.
            return Signal(
                kind: .directionLabel,
                weight: -25,
                detail: "Both pair sides direction-labeled "
                    + "('\(forwardLabel!)' / '\(reverseLabel!)') — paired "
                    + "index advance, not a round-trip codec"
            )
        }
        // V1.12.1 single-side path preserved verbatim — score arithmetic
        // unchanged when only one side is direction-labeled.
        let label = forwardIsDirectional ? forwardLabel! : reverseLabel!
        return Signal(
            kind: .directionLabel,
            weight: -15,
            detail: "Direction-label argument: '\(label)' — pair side is "
                + "likely directional (increment/decrement) rather than a "
                + "true round-trip pair"
        )
    }
}
