import Foundation
import SwiftInferCore

/// Shared scaffold for the V2.0 interaction-invariant template families
/// (Conservation, Idempotence, Cardinality, Referential Integrity,
/// Biconditional).
///
/// Each family differs only in its `family` tag, its per-witness `predicate`,
/// and its explainability prose. The `analyze` fan-out and the
/// `InteractionInvariantSuggestion` assembly were byte-for-byte identical
/// across all five and now live here as default implementations; a conforming
/// family supplies only `family`, `initialScore`, and the three per-witness
/// hooks.
protocol InteractionTemplateFamily {
    associatedtype Witness

    /// The interaction-invariant family this template emits.
    static var family: InteractionInvariantFamily { get }

    /// Initial score for an emitted suggestion (the `.possible` band per
    /// PRD §3.5 corollary until calibration data promotes it).
    static var initialScore: Int { get }

    /// The invariant predicate string for a single witness.
    static func makePredicate(witness: Witness) -> String

    /// "Why suggested" explainability lines for a witness.
    static func whySuggestedFor(witness: Witness, candidate: ReducerCandidate) -> [String]

    /// "Why this might be wrong" caveat lines for a witness.
    static func whyMightBeWrongFor(witness: Witness) -> [String]
}

extension InteractionTemplateFamily {
    /// Emit one suggestion per witness. Pure; no I/O. The caller (the template
    /// engine) is responsible for stamping `firstSeenAt` consistently across
    /// all suggestions emitted in one run.
    static func analyze(
        candidate: ReducerCandidate,
        witnesses: [Witness],
        firstSeenAt: Date
    ) -> [InteractionInvariantSuggestion] {
        witnesses.map { witness in
            makeSuggestion(candidate: candidate, witness: witness, firstSeenAt: firstSeenAt)
        }
    }

    /// Per-witness suggestion construction. Kept accessible (via `@testable`)
    /// so tests can drive it with hand-built (candidate, witness) inputs.
    static func makeSuggestion(
        candidate: ReducerCandidate,
        witness: Witness,
        firstSeenAt: Date
    ) -> InteractionInvariantSuggestion {
        let predicate = makePredicate(witness: witness)
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: family,
            reducerQualifiedName: candidate.qualifiedName,
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: family,
            reducerQualifiedName: candidate.qualifiedName,
            reducerLocation: candidate.location,
            stateTypeName: candidate.stateTypeName,
            actionTypeName: candidate.actionTypeName,
            predicate: predicate,
            score: initialScore,
            tier: tierFor(family: family, score: initialScore),
            whySuggested: whySuggestedFor(witness: witness, candidate: candidate),
            whyMightBeWrong: whyMightBeWrongFor(witness: witness),
            firstSeenAt: firstSeenAt
        )
    }

    /// Cycle 107 — derive the emitted tier from the family's score.
    ///
    /// Through cycles 98–106 every family shipped a hardcoded `.possible`
    /// (the PRD §3.5 corollary: new families stay default-`.possible`
    /// through calibration). Cycle 107 promotes idempotence to `.likely`
    /// by bumping its `initialScore` into the `.likely` band, so the tier
    /// must now follow the score via `Tier(score:)`.
    ///
    /// The one guard: a family carrying a Finding-G SwiftProjectLint
    /// re-home (`swiftProjectLintDeferral != nil` — cardinality +
    /// biconditional) is **clamped to `.possible` regardless of score**.
    /// Those families detect a representable-illegal-state refactor smell,
    /// not a high-precision runtime property (33–50% acceptance), so they
    /// must never promote off the `.possible` tier even if a future score
    /// signal would otherwise lift them. This is the promotion gate the
    /// `swiftProjectLintDeferral` mapping was introduced to back.
    ///
    /// Cycle 112 — the gate now lives on `InteractionInvariantFamily`
    /// (`tier(forScore:)`) so the verify-evidence re-grade shares it; this
    /// stays as the template-emission entry that delegates to it.
    static func tierFor(family: InteractionInvariantFamily, score: Int) -> Tier {
        family.tier(forScore: score)
    }
}
