import Foundation
import SwiftInferCore

/// V2.0 M6 — Referential Integrity interaction-template family. PRD §5.5.
///
/// **What it produces.** One `InteractionInvariantSuggestion` per
/// witness with predicate:
///
///   `state.<selected> == nil || state.<collection>.contains { $0.id == state.<selected> }`
///
/// **Fits M4.D's per-step embedding** — state-level boolean
/// predicate, same shape as Conservation and Cardinality. Engine
/// dispatch + stub-emitter `.referentialIntegrity` arm route
/// through `precondition(<predicate>)` in the per-action loop.
///
/// **Scoring.** Initial score 30 (`.possible` band) per PRD §3.5
/// corollary — default-Possible for three calibration cycles
/// before promotion.
///
/// **Counter-signal documented, not vetoed.** PRD §5.5: "Selection
/// is allowed to be stale by design (e.g., the View interprets a
/// missing selection as 'show empty state') — surfaced as a known
/// caveat in the explainability block, not a veto." The
/// `whyMightBeWrong` block names this so the user understands when
/// to reject the suggestion.
public enum ReferentialIntegrityInteractionTemplate {

    /// V2.0 M6 — initial score. Lands in the `.possible` band
    /// (20–39) per PRD §3.5 corollary.
    static let initialScore = 30

    /// V2.0 M6 — emit one suggestion per witness. Pure; no I/O.
    public static func analyze(
        candidate: ReducerCandidate,
        witnesses: [ReferentialIntegrityWitness],
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
        witness: ReferentialIntegrityWitness,
        firstSeenAt: Date
    ) -> InteractionInvariantSuggestion {
        let predicate = makePredicate(witness: witness)
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .referentialIntegrity,
            reducerQualifiedName: candidate.qualifiedName,
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: .referentialIntegrity,
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

    /// V2.0 M6 — build the "selected is nil OR collection contains
    /// it" predicate from the witness. Pure.
    static func makePredicate(witness: ReferentialIntegrityWitness) -> String {
        "state.\(witness.selectedPropertyName) == nil"
            + " || state.\(witness.collectionPropertyName)"
            + ".contains { $0.id == state.\(witness.selectedPropertyName) }"
    }

    private static func whySuggestedFor(
        witness: ReferentialIntegrityWitness,
        candidate: ReducerCandidate
    ) -> [String] {
        [
            "State stores `\(witness.selectedPropertyName): "
                + "\(witness.selectedTypeName)` paired with "
                + "`\(witness.collectionPropertyName): "
                + "[\(witness.elementTypeName)]` — a referential-"
                + "integrity candidate (PRD §5.5).",
            "Reducer-shaped signature (\(candidate.signatureShape.rawValue)) — "
                + "verifier asserts the selection points to an extant element "
                + "at each action step."
        ]
    }

    private static func whyMightBeWrongFor(
        witness: ReferentialIntegrityWitness
    ) -> [String] {
        [
            "Detection is structural only — reducer-body handlers for "
                + ".select / .delete actions not yet inspected (M6+ refinement). "
                + "The PRD §5.5 third witness ('.select writes to ID + "
                + ".delete clears collection without clearing selection') "
                + "would strengthen this signal.",
            "Predicate uses `\\$0.id ==` against "
                + "`\(witness.elementTypeName)` — the element type must "
                + "conform to `Identifiable` (or expose a comparable `id` "
                + "property) for the synthesized verifier to compile. "
                + "Non-conforming element types surface as "
                + "`.architecturalCoveragePending` per M3.E.3.",
            "PRD §5.5 counter-signal: selection may be allowed to be "
                + "stale by design (e.g., the View interprets a missing "
                + "selection as 'show empty state'). This invariant is "
                + "incorrect in that case — surfaced here as a caveat, not "
                + "as an automatic veto.",
            "Initial-state invariant may not hold if `State.init()` sets "
                + "`\(witness.selectedPropertyName)` to a non-nil value with "
                + "`\(witness.collectionPropertyName)` empty."
        ]
    }
}
