import Foundation
import SwiftInferCore

/// V2.0 M4.C — Idempotence interaction-template family. PRD §5.3.
///
/// **What it produces.** One `InteractionInvariantSuggestion` per
/// `IdempotenceWitness`. The emitted suggestion's `predicate`
/// field carries the bare action-case dot-shorthand
/// (`.refresh` / `.setColor` / etc.) rather than a boolean Swift
/// expression — Idempotence's verifier loop is structurally
/// different from Conservation's:
///
/// ```swift
/// // M4.D will emit code like this for an idempotence suggestion:
/// var initial = State()
/// for action in actions { initial = reduce(initial, action) }
/// let once = reduce(initial, .refresh)
/// let twice = reduce(once, .refresh)
/// #expect(once == twice)
/// ```
///
/// The verifier needs to compute `reduce(state, action)` twice and
/// compare — different shape from Conservation's per-step boolean
/// check. M4.D's stub emitter branches on `suggestion.family`:
///   - `.conservation` → embeds the predicate as
///     `#expect(<predicate>)` inside the per-step loop.
///   - `.idempotence` → emits a dedicated double-apply test using
///     the action-case identifier in `predicate`.
///
/// **Scoring.** Initial score 30 (sits in the `.possible` band)
/// matching Conservation's default-Possible posture (PRD §3.5).
public enum IdempotenceInteractionTemplate: InteractionTemplateFamily {

    static let family = InteractionInvariantFamily.idempotence

    /// V2.0 M4.C — initial score. Same `.possible` band default as
    /// Conservation; calibration may promote (or demote) once real
    /// corpora produce data.
    static let initialScore = 30

    /// V2.0 M4.C — the predicate carries the action-case dot-shorthand.
    /// M4.D's stub emitter parses by family and embeds the appropriate
    /// verifier loop. Pure.
    static func makePredicate(witness: IdempotenceWitness) -> String {
        ".\(witness.actionCaseName)"
    }

    static func whySuggestedFor(
        witness: IdempotenceWitness,
        candidate: ReducerCandidate
    ) -> [String] {
        let patternDescription: String
        switch witness.matchKind {
        case .exactName:
            patternDescription = "exact-match against the curated "
                + "idempotent-action list (refresh / reset / clear / "
                + "dismiss / cancel / close / hide)"

        case .namePrefix:
            patternDescription = "name-prefix match (set* / select* / "
                + "show* / present*) — payload-aware idempotence "
                + "still surfaces under verifier since the same "
                + "payload is generated twice in succession"
        }
        return [
            "Action case `.\(witness.actionCaseName)` matches an "
                + "idempotent-action pattern: \(patternDescription).",
            "Reducer-shaped signature (\(candidate.signatureShape.rawValue))."
        ]
    }

    static func whyMightBeWrongFor(witness: IdempotenceWitness) -> [String] {
        var caveats: [String] = [
            "Detection is purely name-based — reducer-body purity for "
                + "this action is not yet inspected (M4.C+ refinement). "
                + "An action body that increments counters or accumulates "
                + "into unbounded collections breaks idempotence even when "
                + "the name suggests otherwise."
        ]
        if witness.matchKind == .namePrefix {
            caveats.append(
                "Prefix-match families (set* / select* / etc.) are idempotent "
                    + "only when the action's payload is held constant. The "
                    + "verifier generates the same payload twice in succession, "
                    + "so detection still surfaces correctly, but the property "
                    + "doesn't extend to 'all payloads' uniformly."
            )
        }
        return caveats
    }
}
