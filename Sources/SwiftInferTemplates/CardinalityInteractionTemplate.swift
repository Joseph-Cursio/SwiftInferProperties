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
public enum CardinalityInteractionTemplate: InteractionTemplateFamily {

    static let family = InteractionInvariantFamily.cardinality

    /// V2.0 M5 — initial score. Lands in the `.possible` band
    /// (20–39) per PRD §3.5 corollary.
    static let initialScore = 30

    /// V2.0 M5 — build the `Σ indicators ≤ 1` predicate from the
    /// witness's fields. Each indicator is wrapped in a
    /// `(<indicator> ? 1 : 0)` ternary so the sum is well-typed.
    static func makePredicate(witness: CardinalityWitness) -> String {
        let terms = witness.fields.map { "(\($0.indicator) ? 1 : 0)" }
        let sum = terms.joined(separator: " + ")
        return "\(sum) <= 1"
    }

    static func whySuggestedFor(
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

    static func whyMightBeWrongFor(witness _: CardinalityWitness) -> [String] {
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
                + "state.",
            crossReferenceCaveat
        ]
    }

    /// V2.0 Finding G — cross-reference to the SwiftProjectLint refactor
    /// lint. This is the *same* signal seen as a structural smell rather
    /// than a runtime property: ≥ 2 presentation fields make an illegal
    /// both-active state *representable*. The generated test can false-fail
    /// because the mutex is often enforced by the presentation framework
    /// (a modal auto-nils on dismiss) that this reducer-level test does not
    /// model — so a failure may flag a UI-unreachable state, not a bug.
    /// We still emit the property (a failure may instead be a genuinely
    /// unguarded state), but pin it at `.possible` per the cycle-104 gate.
    private static var crossReferenceCaveat: String {
        let rule = family.swiftProjectLintDeferral ?? ""
        return "This is also a representable-illegal-state refactor smell "
            + "— see SwiftProjectLint rule `\(rule)`. The mutex may be "
            + "enforced by the presentation framework (modal auto-dismiss) "
            + "that this reducer-level test doesn't model, so a failing test "
            + "can flag a UI-unreachable state rather than a bug. The "
            + "idiomatic fix collapses the fields into a single `@Presents` "
            + "destination enum, which makes the illegal state "
            + "unrepresentable (Finding G)."
    }
}
