import Foundation
import SwiftInferCore

/// V2.0 M5 — Cardinality interaction-template family. PRD §5.4.
/// First *new* family (Conservation + Idempotence at M4.B/C were
/// lifted from v1).
///
/// **What it produces.** One `InteractionInvariantSuggestion` per
/// witness — at most one per State struct, since a Cardinality
/// witness encompasses every detected presentation field. The
/// emitted predicate sums per-field indicators and asserts ≤ 1:
///
///   `(state.activeSheet != nil ? 1 : 0) + ...`
///   `... + (state.isFullScreen ? 1 : 0) <= 1`
///
/// **Fits M4.D's per-step embedding.** Cardinality's predicate is
/// a state-level boolean — the same shape as Conservation's. M4.D's
/// `makePerStepCheck` routes it through `precondition(<predicate>)`
/// inside the per-action loop, no new stub-emitter shape needed.
///
/// **Scoring.** Initial score 30 (lands in `.possible` band)
/// matching the other new-family defaults per PRD §3.5 corollary
/// — three calibration cycles before promotion. PRD §5.4 also
/// flags the "≥ 2 fields" detection as deliberately crude; future
/// cycles may add per-field-count score signals.
public enum CardinalityInteractionTemplate {

    /// V2.0 M5 — initial score. Lands in the `.possible` band
    /// (20–39) per PRD §3.5 corollary.
    static let initialScore = 30

    /// V2.0 M5 — emit one suggestion per witness. Pure; no I/O.
    public static func analyze(
        candidate: ReducerCandidate,
        witnesses: [CardinalityWitness],
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
    /// tests can drive it with hand-built inputs.
    static func makeSuggestion(
        candidate: ReducerCandidate,
        witness: CardinalityWitness,
        firstSeenAt: Date
    ) -> InteractionInvariantSuggestion {
        let predicate = makePredicate(witness: witness)
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .cardinality,
            reducerQualifiedName: candidate.qualifiedName,
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: .cardinality,
            reducerQualifiedName: candidate.qualifiedName,
            reducerLocation: candidate.location,
            stateTypeName: candidate.stateTypeName,
            actionTypeName: candidate.actionTypeName,
            predicate: predicate,
            score: initialScore,
            tier: .possible,
            whySuggested: whySuggestedFor(witness: witness, candidate: candidate),
            whyMightBeWrong: whyMightBeWrongFor(witness: witness),
            firstSeenAt: firstSeenAt
        )
    }

    /// V2.0 M5 — build the `Σ indicators ≤ 1` predicate from the
    /// witness's fields. Each indicator is wrapped in a
    /// `(<indicator> ? 1 : 0)` ternary so the sum is well-typed.
    static func makePredicate(witness: CardinalityWitness) -> String {
        let terms = witness.fields.map { "(\($0.indicator) ? 1 : 0)" }
        let sum = terms.joined(separator: " + ")
        return "\(sum) <= 1"
    }

    private static func whySuggestedFor(
        witness: CardinalityWitness,
        candidate: ReducerCandidate
    ) -> [String] {
        let boolCount = witness.fields.filter { $0.kind == .boolFlag }.count
        let optionalCount = witness.fields.filter { $0.kind == .optionalPresentation }.count
        let fieldList = witness.fields.map(\.propertyName).joined(separator: ", ")
        return [
            "State has \(witness.fields.count) presentation-shaped "
                + "fields (\(boolCount) Bool flag\(boolCount == 1 ? "" : "s")"
                + ", \(optionalCount) Optional "
                + "presentation\(optionalCount == 1 ? "" : "s")): \(fieldList).",
            "Reducer-shaped signature (\(candidate.signatureShape.rawValue)) — "
                + "verifier loop will assert ≤ 1 active at each action step."
        ]
    }

    private static func whyMightBeWrongFor(witness _: CardinalityWitness) -> [String] {
        [
            "Detection is structural only — reducer-body handlers for "
                + ".show* actions are not yet inspected (M5+ refinement). "
                + "If your domain allows two presentations active "
                + "simultaneously by design (e.g. an alert overlaid on "
                + "a sheet), this invariant is incorrect.",
            "The `≥ 2 fields` heuristic is deliberately crude (PRD §5.4 "
                + "calibration note). Spurious matches on fields that "
                + "happen to contain `Showing` / `Presenting` / `sheet` / "
                + "`alert` etc. are expected in the first calibration "
                + "cycles.",
            "Initial-state invariant may not hold if `State.init()` "
                + "leaves multiple fields in their non-default active "
                + "state."
        ]
    }
}
