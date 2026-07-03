import Foundation
import SwiftInferCore

/// V2.0 Phase 2 — Determinism interaction-template family.
///
/// **What it produces.** Exactly one `InteractionInvariantSuggestion` per
/// reducer candidate, for **every** carrier — redux *and* TCA. Determinism is
/// a universal reducer guarantee, and a road-test against real Point-Free code
/// showed 100% of real-world reducers are `carrier:tca`, so excluding TCA left
/// the family with near-zero reach. Unlike the other five families, determinism
/// has **no witness detector**: it isn't a State-shape or Action-name pattern,
/// it's the paradigm-level purity guarantee `reduce(s, a) == reduce(s, a)`. The
/// "witness" is therefore the candidate itself (the engine passes `[candidate]`).
///
/// **Carrier specialisation.** The template surfaces uniformly; the stub
/// (`makeDeterminismCheck`) specialises: `.tca` runs the two applications with
/// declared `@Dependencies` pinned to constants (so the check flags a reducer
/// sneaking a raw `Date()`/`UUID()`/`random()` into state instead of routing it
/// through `@Dependency` — the TCA anti-pattern), while redux/elm/mobius do a
/// plain double-apply.
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
        let carrierNote = candidate.carrierKind == .tca
            ? "TCA reducer — verified with declared @Dependencies pinned to "
                + "constants, so this checks that all nondeterminism is routed "
                + "through @Dependency (no raw Date()/UUID()/random() in state)."
            : "reducer (\(candidate.carrierKind.rawValue)) — a "
                + "`(State, Action) -> State` reducer should be a pure, "
                + "deterministic function."
        return [
            carrierNote,
            "Reducer-shaped signature (\(candidate.signatureShape.rawValue)); "
                + "static purity label: \(candidate.purity.rawValue)."
        ]
    }

    static func whyMightBeWrongFor(witness _: ReducerCandidate) -> [String] {
        [
            "Measured by applying the same (state, action) twice and comparing "
                + "results — a reducer that reads `Date()` / `UUID()` / "
                + "`.random()` / a global directly (not via @Dependency) will "
                + "fail. That is a true negative (the reducer really isn't "
                + "deterministic), not a false positive.",
            "Requires State: Equatable and a constructible Action alphabet; an "
                + "unsupported shape / non-constructible State reports "
                + "architectural-coverage-pending rather than a pass/fail. For "
                + "TCA, `withRandomNumberGenerator` is not yet pinned, so a "
                + "reducer using it synchronously may report a false failure."
        ]
    }

    /// Emit one determinism suggestion per reducer candidate — for **every**
    /// carrier (redux *and* TCA). Determinism is a universal reducer guarantee;
    /// the stub specialises per carrier (`makeDeterminismCheck` pins
    /// @Dependencies for `.tca`, plain double-apply for the rest). Surfacing is
    /// unconditional (no State-constructibility pre-gate): the suggestion ships
    /// at Possible (hidden by default), and verify honestly reports
    /// architectural-coverage-pending for non-constructible State/Action rather
    /// than silently dropping it.
    static func analyze(
        candidate: ReducerCandidate,
        firstSeenAt: Date
    ) -> [InteractionInvariantSuggestion] {
        analyze(candidate: candidate, witnesses: [candidate], firstSeenAt: firstSeenAt)
    }
}
