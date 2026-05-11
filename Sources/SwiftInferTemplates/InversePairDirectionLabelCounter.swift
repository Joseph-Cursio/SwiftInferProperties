import SwiftInferCore

/// V1.11.1 — direction-label counter-signal extension on
/// `InversePairTemplate`. Closes cycle-8 priority #1 from
/// `docs/calibration-cycle-7-findings.md` (inverse-pair 0/5 acceptance
/// rate per cycle-6's measurement). Mirrors v1.10's
/// `IdempotenceTemplate` direction-label counter; reuses the curated
/// 10-element `DirectionLabels.curated` set verbatim — cross-template
/// signal reuse per cycle-8's design intent.
///
/// File-split per the V1.6.1 / V1.8.1 / V1.10.1 file-length precedent
/// (`InversePairTemplate.swift` was 1 line over swiftlint's
/// `type_body_length: 250` budget when this helper landed inline).
///
/// **V1.13.1.** Updated to consume `SwiftInferCore.DirectionLabels.curated`
/// (hoisted from `IdempotenceTemplate.directionLabels` once round-trip
/// became the third consumer in cycle 9).
extension InversePairTemplate {

    /// Fires when *either* side of the pair's first-parameter argument
    /// label is in `DirectionLabels.curated` (e.g.,
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
        let forwardIsDirection = forwardLabel.map { DirectionLabels.curated.contains($0) } ?? false
        let reverseIsDirection = reverseLabel.map { DirectionLabels.curated.contains($0) } ?? false
        guard forwardIsDirection || reverseIsDirection else {
            return nil
        }
        let cursorPrefixes = ["index", "bucket", "word"]
        let forwardName = pair.forward.name
        let reverseName = pair.reverse.name
        let forwardNameMatch = cursorPrefixes.contains { forwardName.hasPrefix($0) }
        let reverseNameMatch = cursorPrefixes.contains { reverseName.hasPrefix($0) }
        // V1.27.B — name-prefix-gated full veto. Direct cycle-23 finding
        // closure (cycle-23 #26 `bucket(after:) × bucket(before:)` +
        // #27 `word(after:) × word(before:)` REJECT). When BOTH pair
        // sides are direction-labeled AND both function names start with
        // `index`/`bucket`/`word`, fire full veto. Mirrors V1.25.A on
        // idempotence + V1.22.B on round-trip.
        if forwardIsDirection && reverseIsDirection,
           forwardNameMatch && reverseNameMatch {
            return Signal(
                kind: .directionLabel,
                weight: Signal.vetoWeight,
                detail: "Both pair sides direction-labeled + name-prefix "
                    + "match ('\(forwardName)(\(forwardLabel!):)' × "
                    + "'\(reverseName)(\(reverseLabel!):)') — positional "
                    + "cursor-advance pair, not a functional-inverse pair"
            )
        }
        // V1.29.A — asymmetric-pair full veto. Direct cycle-25 finding 1
        // closure (cycle-25 #28 `bucket(after:) × firstOccupiedBucketInChain`
        // + #29 `bucket(before:) × firstOccupiedBucketInChain` REJECT). When
        // ONE side is a cursor-advance shape (direction-labeled + name in
        // {index,bucket,word}) and the OTHER side is not direction-labeled,
        // the pair is structurally asymmetric (cursor-advance × search-shape)
        // rather than functional-inverse. Fire full veto. Mirrors V1.27.B's
        // symmetric-veto pattern.
        if forwardIsDirection != reverseIsDirection {
            let cursorSideIsForward = forwardIsDirection
            let cursorSideName = cursorSideIsForward ? forwardName : reverseName
            let cursorSideLabel = cursorSideIsForward ? forwardLabel! : reverseLabel!
            let otherSideName = cursorSideIsForward ? reverseName : forwardName
            let cursorSideNameMatch = cursorSideIsForward ? forwardNameMatch : reverseNameMatch
            if cursorSideNameMatch {
                return Signal(
                    kind: .directionLabel,
                    weight: Signal.vetoWeight,
                    detail: "Asymmetric direction-pair: cursor-advance side "
                        + "'\(cursorSideName)(\(cursorSideLabel):)' × non-direction "
                        + "side '\(otherSideName)(...)' — cursor advance is not a "
                        + "functional-inverse partner to a search-shape lookup"
                )
            }
        }
        // V1.11.1 either-side path preserved verbatim: single-side or
        // non-prefix-match direction labels fire at -10.
        let label = forwardIsDirection ? forwardLabel! : reverseLabel!
        return Signal(
            kind: .directionLabel,
            weight: -10,
            detail: "Direction-label argument: '\(label)' — pair side is "
                + "likely directional (increment/decrement) rather than a "
                + "true inverse pair"
        )
    }
}
