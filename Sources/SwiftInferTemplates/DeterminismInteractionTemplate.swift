import Foundation
import SwiftInferCore

/// V2.0 Phase 2 (Redux) — Determinism interaction-template family.
///
/// **What it produces.** Exactly one `InteractionInvariantSuggestion` per
/// `.redux`-family reducer candidate (TCA excluded — its own richer story).
/// Unlike the other five families, determinism has **no witness detector**:
/// it isn't a State-shape or Action-name pattern, it's the paradigm-level
/// purity guarantee `reduce(s, a) == reduce(s, a)` that every pure reducer
/// owns. The "witness" is therefore the candidate itself; the engine passes
/// `[candidate]` for a redux carrier and `[]` otherwise.
///
/// **Why it's worth verifying even though pure reducers pass trivially.**
/// The static purity analyzer (`ReducerPurityAnalyzer`) rules out TCA
/// effects and hidden mutation but does **not** inspect for a hidden
/// `Date()` / `UUID()` / `.random()` / global read. Those slip through as
/// `.pure` yet make two applications of the same `(state, action)` differ —
/// the runtime determinism check is exactly what catches them
/// (`measuredDefaultFails`). A reducer that legitimately reads the clock is
/// a true negative, not a tool bug.
///
/// **Predicate.** A fixed documentary string; determinism's stub
/// (`ActionSequenceStubEmitter.makeDeterminismCheck`) is a per-step two-call
/// comparison over the loop variables and does not embed the predicate.
///
/// **Scoring.** Ships at 30 (`.possible`) per the PRD §3.5 corollary — a
/// new family stays default-`.possible` until calibration data promotes it.
/// A measured `bothPass` folds +50 → `.strong` → `.verified` through the
/// existing M9 evidence→tier join (determinism carries no Finding-G
/// deferral, so the fold is not clamped).
public enum DeterminismInteractionTemplate: InteractionTemplateFamily {

    static let family = InteractionInvariantFamily.determinism

    static let initialScore = 30

    static func makePredicate(witness _: ReducerCandidate) -> String {
        "reduce(s, a) == reduce(s, a)"
    }

    static func whySuggestedFor(
        witness _: ReducerCandidate,
        candidate: ReducerCandidate
    ) -> [String] {
        [
            "Redux-family reducer (\(candidate.carrierKind.rawValue)) — a "
                + "`(State, Action) -> State` reducer should be a pure, "
                + "deterministic function.",
            "Reducer-shaped signature (\(candidate.signatureShape.rawValue)); "
                + "static purity label: \(candidate.purity.rawValue)."
        ]
    }

    static func whyMightBeWrongFor(witness _: ReducerCandidate) -> [String] {
        [
            "Measured by applying the same (state, action) twice and comparing "
                + "results — a reducer that legitimately reads `Date()` / "
                + "`UUID()` / `.random()` / a global will fail. That is a true "
                + "negative (the reducer really isn't deterministic), not a "
                + "false positive.",
            "Requires State: Equatable and a constructible Action alphabet; "
                + "an unsupported shape reports architectural-coverage-pending "
                + "rather than a pass/fail."
        ]
    }

    /// Emit a determinism suggestion for a `.redux`-family candidate, or an
    /// empty slice for TCA / non-reducer carriers. The witness list is
    /// `[candidate]` (one suggestion) when redux, `[]` otherwise — so this
    /// reuses the protocol's per-witness `analyze` fan-out unchanged.
    static func analyze(
        candidate: ReducerCandidate,
        firstSeenAt: Date
    ) -> [InteractionInvariantSuggestion] {
        let witnesses = candidate.carrierKind.isReduxFamily ? [candidate] : []
        return analyze(candidate: candidate, witnesses: witnesses, firstSeenAt: firstSeenAt)
    }
}
