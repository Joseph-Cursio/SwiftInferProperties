import Foundation
import SwiftInferCore

/// V2.0 M7 — Biconditional / iff interaction-template family. PRD §5.6.
///
/// **What it produces.** One `InteractionInvariantSuggestion` per
/// witness with predicate:
///
///   `state.<bool> == (state.<optional> != nil)`
///
/// **Fits M4.D's per-step embedding.** State-level boolean — same
/// shape as Conservation, Cardinality, and Referential Integrity.
/// `ActionSequenceStubEmitter.makePerStepCheck` routes
/// `.biconditional` through `precondition(<predicate>)`.
///
/// **Scoring.** Initial score 30 (`.possible` band) per PRD §3.5
/// corollary. PRD §5.6 calibration note flags this as the trickiest
/// of the five families — expect 3–5 calibration cycles before
/// promotion (longer than the other families' baseline 3).
public enum BiconditionalInteractionTemplate: InteractionTemplateFamily {

    static let family = InteractionInvariantFamily.biconditional

    /// V2.0 M7 — initial score. Lands in the `.possible` band
    /// (20–39) per PRD §3.5 corollary.
    static let initialScore = 30

    /// V2.0 M7 — `state.<bool> == (state.<optional> != nil)`. Pure.
    static func makePredicate(witness: BiconditionalWitness) -> String {
        "state.\(witness.boolPropertyName)"
            + " == (state.\(witness.optionalPropertyName) != nil)"
    }

    static func whySuggestedFor(
        witness: BiconditionalWitness,
        candidate: ReducerCandidate
    ) -> [String] {
        [
            "State stores `\(witness.boolPropertyName): "
                + "\(witness.boolTypeName)` paired with "
                + "`\(witness.optionalPropertyName): "
                + "\(witness.optionalTypeName)` — a biconditional candidate "
                + "(PRD §5.6).",
            "Reducer-shaped signature (\(candidate.signatureShape.rawValue)) — "
                + "verifier asserts the two projected Bools agree at each "
                + "action step (whole-State Equatable not required)."
        ]
    }

    static func whyMightBeWrongFor(witness: BiconditionalWitness) -> [String] {
        [
            "Detection is structural only — reducer-body handlers for "
                + ".startX / .cancelX actions not yet inspected (PRD §5.6 "
                + "third witness). The third witness ('at least one "
                + "handler clears only one of the pair') is the signal that "
                + "this invariant *should* hold; without it, M7 may surface "
                + "pairs whose two sides are intentionally independent.",
            "Pairing is Cartesian-product at v0.0 — every `is*`-shaped "
                + "Bool × every Optional in the State. Spurious matches "
                + "are expected in the first calibration cycles; stem-"
                + "matching (`isLoadingX` ↔ `taskX?`) is a future "
                + "refinement.",
            "PRD §5.6 calibration note: this family is the trickiest of "
                + "the five because the two sides often live in different "
                + "state layers (view-state vs model-state) and drift out "
                + "of sync — exactly where SwiftUI race conditions show "
                + "up. Expect 3–5 calibration cycles before stable "
                + "acceptance rate.",
            "Initial-state invariant may not hold if `State.init()` sets "
                + "`\(witness.boolPropertyName)` to `true` with "
                + "`\(witness.optionalPropertyName) == nil` (or vice versa).",
            crossReferenceCaveat
        ]
    }

    /// V2.0 Finding G — cross-reference to the SwiftProjectLint refactor
    /// lint. The same flag/optional pair seen as a structural smell rather
    /// than a runtime property: it makes a loading-with-stale-result (or
    /// loaded-but-flag-off) state *representable*. The generated test can
    /// false-fail because the two fields are often orthogonal *at rest* —
    /// e.g. a fetched value that legitimately persists after the loading
    /// flag clears — so the biconditional is false at rest by design, not
    /// a bug. We still emit the property (a failure may instead be a real
    /// drift between the pair), but pin it at `.possible` per the
    /// cycle-104 gate.
    private static var crossReferenceCaveat: String {
        let rule = family.swiftProjectLintDeferral ?? ""
        return "This is also a representable-illegal-state refactor smell "
            + "— see SwiftProjectLint rule `\(rule)`. The flag and the "
            + "optional are often orthogonal at rest (a value that persists "
            + "after the flag clears), so the predicate can be false at rest "
            + "by design rather than from a bug. The idiomatic fix models "
            + "the pair as a single `enum Status { case idle, loading, "
            + "loaded(T) }`, which makes the illegal combination "
            + "unrepresentable (Finding G)."
    }
}
