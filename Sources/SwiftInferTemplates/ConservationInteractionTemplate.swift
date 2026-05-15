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
public enum ConservationInteractionTemplate {

    /// V2.0 M4.B — initial score for a Conservation suggestion.
    /// Sits inside the `.possible` band (20–39). Calibration may
    /// promote (or demote) this once real corpora produce data.
    static let initialScore = 30

    /// V2.0 M4.B — emit one suggestion per witness. Pure; no I/O.
    /// Caller (the template engine) is responsible for stamping
    /// `firstSeenAt` consistently across all suggestions emitted in
    /// one run.
    public static func analyze(
        candidate: ReducerCandidate,
        witnesses: [ConservationWitness],
        firstSeenAt: Date
    ) -> [InteractionInvariantSuggestion] {
        witnesses.map { witness in
            makeSuggestion(
                candidate: candidate,
                witness: witness,
                firstSeenAt: firstSeenAt
            )
        }
    }

    /// Per-witness suggestion construction. Pulled to a static so
    /// tests can drive it with hand-built (candidate, witness)
    /// inputs.
    static func makeSuggestion(
        candidate: ReducerCandidate,
        witness: ConservationWitness,
        firstSeenAt: Date
    ) -> InteractionInvariantSuggestion {
        let predicate = "state.\(witness.aggregatePropertyName)"
            + " == state.\(witness.collectionPropertyName).count"
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .conservation,
            reducerQualifiedName: candidate.qualifiedName,
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: .conservation,
            reducerQualifiedName: candidate.qualifiedName,
            reducerLocation: candidate.location,
            stateTypeName: candidate.stateTypeName,
            actionTypeName: candidate.actionTypeName,
            predicate: predicate,
            score: initialScore,
            tier: .possible,
            whySuggested: [
                "State stores `\(witness.aggregatePropertyName): "
                    + "\(witness.aggregateTypeName)` paired with "
                    + "`\(witness.collectionPropertyName): "
                    + "[\(witness.elementTypeName)]` — a count-shaped "
                    + "conservation candidate (PRD §5.2).",
                "Reducer-shaped signature (\(candidate.signatureShape.rawValue))."
            ],
            whyMightBeWrong: [
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
            ],
            firstSeenAt: firstSeenAt
        )
    }
}
