import SwiftInferCore

/// First-parameter-label veto signals for `CompositionTemplate`. Extracted
/// from `CompositionTemplate.swift` (file_length). Each fires a full
/// `Signal.vetoWeight` veto when the lifted method's first user-facing
/// parameter carries a label that names something *other than an additive
/// addend*, so the additive-monoid composition law `op(s, a + b) ==
/// op(op(s, a), b)` cannot hold. The label sets themselves
/// (`monotoneBoundedLabels` / `positionalShiftLabels` /
/// `simulationControlLabels`) stay on the enum next to their dogfood
/// provenance.
extension CompositionTemplate {

    /// V1.21.B / **V1.29.C** — fires when the first non-self parameter's
    /// label is in `monotoneBoundedLabels`. V1.21.B introduced a `-25`
    /// counter-signal demoting Strong → Likely. V1.29.C promotes to a
    /// full `Signal.vetoWeight` veto per the cycle-25 4-cycle-stable-
    /// reject finding on `advance(until:)` (cycles 17 + 20 + 23 + 25).
    /// Returns `nil` for non-monotone-bounded labels (including `nil`
    /// label and `by:`).
    ///
    /// The lift's `liftedParameters[0]` is always the implicit-self
    /// binding (per `LiftedTransformation.lift`); the user-facing first
    /// parameter is `originalSummary.parameters[0]`. The composition
    /// shape gate already enforces `originalParams.count == 1`, so we
    /// safely read `[0]`.
    static func monotoneBoundedLabelSignal(
        for lifted: LiftedTransformation
    ) -> Signal? {
        guard let firstParam = lifted.originalSummary.parameters.first,
              let label = firstParam.label,
              monotoneBoundedLabels.contains(label) else {
            return nil
        }
        return Signal(
            kind: .directionLabel,
            weight: Signal.vetoWeight,
            detail: "Monotone-bounded parameter label '\(label)' — "
                + "`op(s, a).op(s, b) = max(a, b)`-bounded state, not "
                + "additive composition `op(s, a + b)`"
        )
    }

    /// Dogfood finding (`attaswift/BigInt`) — fires a full veto when the
    /// first parameter's label is in `positionalShiftLabels` (a place-value
    /// position, not an addend). Mirrors `monotoneBoundedLabelSignal`'s
    /// shape; `nil` label and `by:` are excluded (genuinely additive).
    static func positionalShiftLabelSignal(
        for lifted: LiftedTransformation
    ) -> Signal? {
        guard let firstParam = lifted.originalSummary.parameters.first,
              let label = firstParam.label,
              positionalShiftLabels.contains(label) else {
            return nil
        }
        return Signal(
            kind: .directionLabel,
            weight: Signal.vetoWeight,
            detail: "Positional/shift parameter label '\(label)' — names a "
                + "place-value position, not an additive quantity; `op` at "
                + "distinct positions does not compose additively "
                + "(`op(s, a).op(s, b) ≠ op(s, a + b)`)"
        )
    }

    /// Dogfood finding (`SwiftMarkdownWiki`) — fires a full veto when the
    /// first parameter's label is in `simulationControlLabels` (a
    /// per-iteration simulation control / clamp, not an addend). Mirrors
    /// `monotoneBoundedLabelSignal`'s shape; `nil` label and `by:` are
    /// excluded (genuinely additive).
    static func simulationControlLabelSignal(
        for lifted: LiftedTransformation
    ) -> Signal? {
        guard let firstParam = lifted.originalSummary.parameters.first,
              let label = firstParam.label,
              simulationControlLabels.contains(label) else {
            return nil
        }
        return Signal(
            kind: .directionLabel,
            weight: Signal.vetoWeight,
            detail: "Simulation-control parameter label '\(label)' — names a "
                + "per-iteration control/clamp, not an additive quantity; "
                + "advancing the simulation twice with two clamps is not one "
                + "step with a summed clamp (`op(s, a).op(s, b) ≠ op(s, a + b)`)"
        )
    }
}
