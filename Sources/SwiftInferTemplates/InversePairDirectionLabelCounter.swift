import SwiftInferCore

/// V1.11.1 — direction-label counter-signal extension on
/// `InversePairTemplate`. Closes cycle-8 priority #1 from
/// `docs/calibration-cycle-7-findings.md` (inverse-pair 0/5 acceptance
/// rate per cycle-6's measurement). Mirrors v1.10's
/// `IdempotenceTemplate` direction-label counter; reuses the curated
/// 10-element `IdempotenceTemplate.directionLabels` set verbatim —
/// cross-template signal reuse per cycle-8's design intent.
///
/// File-split per the V1.6.1 / V1.8.1 / V1.10.1 file-length precedent
/// (`InversePairTemplate.swift` was 1 line over swiftlint's
/// `type_body_length: 250` budget when this helper landed inline).
extension InversePairTemplate {

    /// Fires when *either* side of the pair's first-parameter argument
    /// label is in `IdempotenceTemplate.directionLabels` (e.g.,
    /// `index(after:) ↔ index(before:)`,
    /// `bucket(after:) ↔ bucket(before:)`).
    ///
    /// Either-side detection (vs forward-only): asymmetric labeling
    /// like `transform(_:) × untransform(after:)` would be missed by
    /// a forward-only check. Either-side has no false-positive cost
    /// at the `-10` weight because curated/project name matches
    /// preserve Possible tier (`+25 + 10 − 10 = +25`).
    ///
    /// Score arithmetic for inverse-pair (baseline `+25` vs
    /// idempotence's `+30`):
    /// - bare typeSymmetry (`+25`) `− 10` = `+15` → Suppressed (< 20).
    /// - typeSymmetry + curated/project name (`+10`) `− 10` = `+25`
    ///   → Possible (clean margin from the `+20` boundary).
    ///
    /// Weight `-10` (not v1.10's `-15`): inverse-pair's baseline is
    /// `+25`, not `+30`, so `-10` already drops bare-shape pairs into
    /// Suppressed cleanly while keeping curated-name matches above
    /// the `+20` boundary. v1.10's open-decision-#1 rationale (avoid
    /// the noisy ±boundary zone) applies here in the inverse direction.
    ///
    /// **Cycle-6 motivation.** The cycle-6 single-runner triage showed
    /// inverse-pair acceptance at 0/5 = 0% on the post-V1.8.1 surface;
    /// 2 of 5 rejected picks were direction-labeled (Algorithms
    /// `(Index) -> Index` ops, picks #48-#49). The other 3 of 5 are
    /// SetAlgebra-shaped OrderedSet binary ops without direction
    /// labels — separate cause-of-noise class for cycle-9.
    static func directionLabelCounterSignal(
        for pair: FunctionPair
    ) -> Signal? {
        let forwardLabel = pair.forward.parameters.first?.label
        let reverseLabel = pair.reverse.parameters.first?.label
        let matched = [forwardLabel, reverseLabel]
            .compactMap { $0 }
            .first(where: { IdempotenceTemplate.directionLabels.contains($0) })
        guard let label = matched else {
            return nil
        }
        return Signal(
            kind: .directionLabel,
            weight: -10,
            detail: "Direction-label argument: '\(label)' — pair side is "
                + "likely directional (increment/decrement) rather than a "
                + "true inverse pair"
        )
    }
}
