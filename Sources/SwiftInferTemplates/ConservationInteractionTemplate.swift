import Foundation
import SwiftInferCore

/// V2.0 M4.B — Conservation interaction-template family. PRD §5.2.
///
/// **What it produces.** Given a `ReducerCandidate` + one or more
/// `ConservationWitness` values detected in the candidate's State
/// struct, emits one `InteractionInvariantSuggestion` per witness
/// with predicate:
///
///   `state.<aggregate> == state.<collection>.count`
///
/// **Scoring (M4.B initial weights).** Per PRD §3.5 corollary —
/// every new family ships at default `.possible` visibility through
/// three calibration cycles. Initial score baked in at 30, which
/// lands solidly in the 20–39 `.possible` band:
///
///   - Reducer-shaped signature: implicit +30 (gate — required for any
///     interaction suggestion).
///   - Count-shaped aggregate + array collection in State: +30 (the
///     structural witness, M4.B's load-bearing signal).
///   - Per-candidate score caps at 30 until calibration shows the
///     family produces ≥ 70% acceptance rate over three cycles, at
///     which point M5+ promotes by adding more signals (action
///     enum + reducer body coverage) rather than reweighting the
///     existing ones.
///
/// Floating-point aggregates and non-Equatable State are excluded
/// at the witness-detection stage (M4.B detector filters them out)
/// rather than as veto counter-signals here — the witness simply
/// doesn't form. This keeps the template's scoring code clean.
public enum ConservationInteractionTemplate: InteractionTemplateFamily {

    static let family = InteractionInvariantFamily.conservation

    /// V2.0 M4.B — initial score for a Conservation suggestion.
    /// Sits inside the `.possible` band (20–39). Calibration may
    /// promote (or demote) this once real corpora produce data.
    static let initialScore = 30

    /// V2.0 M4.B — `state.<aggregate> == state.<collection>.count`. Pure.
    static func makePredicate(witness: ConservationWitness) -> String {
        "state.\(witness.aggregatePropertyName)"
            + " == state.\(witness.collectionPropertyName).count"
    }

    static func whySuggestedFor(
        witness: ConservationWitness,
        candidate: ReducerCandidate
    ) -> [String] {
        [
            "State stores `\(witness.aggregatePropertyName): "
                + "\(witness.aggregateTypeName)` paired with "
                + "`\(witness.collectionPropertyName): "
                + "[\(witness.elementTypeName)]` — a count-shaped "
                + "conservation candidate (PRD §5.2).",
            "Reducer-shaped signature (\(candidate.signatureShape.rawValue))."
        ]
    }

    static func whyMightBeWrongFor(witness: ConservationWitness) -> [String] {
        [
            "Detection is structural only — Action enum + reducer body "
                + "handlers not yet inspected (M4.B+ refinement).",
            "Predicate uses `\(witness.collectionPropertyName).count` as "
                + "the recompute; correct for count-shaped aggregates but "
                + "wrong for sum / total / subtotal shapes (those need "
                + "per-element field detection — deferred to later M4.B "
                + "refinement).",
            "Initial-state invariant might not hold if `State.init()` sets "
                + "`\(witness.aggregatePropertyName)` to a non-zero default "
                + "with `\(witness.collectionPropertyName)` empty."
        ]
    }
}
