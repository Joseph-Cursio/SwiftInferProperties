import Foundation

/// Cycle 112 — verify-as-signal post-pass for interaction-invariant
/// suggestions: the `InteractionInvariantSuggestion` analogue of the
/// algebraic `VerifyEvidenceScoring`. Folds persisted `verify-interaction`
/// outcomes — written by `VerifyInteractionPipeline.recordEvidence`
/// (cycle 111) — into the suggestion grade, so measured execution can
/// promote, or veto, a pick rather than only annotate it. This is the
/// consumer half of the cycle-110/111/112 "M9" join.
///
/// - `.measuredBothPass` → add `VerifyEvidenceScoring.verifyBothPassWeight`
///   (+50, shared with the algebraic fold so the two stay calibrated
///   together) to the score, recompute the tier **through the family's
///   Finding-G gate** (`InteractionInvariantFamily.tier(forScore:)`), then
///   apply `Tier.promoted(byVerifyOutcome:)`. For idempotence this lifts a
///   `.likely` pick (score 40) to `.verified` (40 + 50 = 90 → `.strong` →
///   `.verified`). For a `swiftProjectLintDeferral` family (cardinality,
///   biconditional) the gate pins `.possible` regardless of evidence — a
///   representable-illegal-state refactor smell never promotes off
///   `.possible`, even when measured.
/// - `.measuredDefaultFails` → collapse to `.suppressed`; discover drops
///   it. An executed counterexample is not a heuristic guess — the same
///   precision argument that backs the algebraic veto (cycle 63).
/// - `.measuredEdgeCaseAdvisory` / `.measuredError` /
///   `.architecturalCoveragePending` are not verdicts → score-neutral
///   pass-through.
///
/// Pure and order-preserving. The `discover-interaction` render path runs
/// it once `verify-evidence.json` is loaded, **before** the visibility cut,
/// so a `bothPass` lift can clear the cut and a `defaultFails` veto drops
/// below it. A suggestion with no evidence passes through unchanged
/// (identical value, so callers can rely on `==`).
public enum InteractionVerifyEvidenceScoring {

    /// Fold `evidenceByIdentity` into `suggestions`, keyed by
    /// `suggestion.identity.normalized` — the exact key the cycle-111
    /// producer writes.
    public static func applied(
        to suggestions: [InteractionInvariantSuggestion],
        evidenceByIdentity: [String: VerifyEvidence]
    ) -> [InteractionInvariantSuggestion] {
        suggestions.map { suggestion in
            guard let evidence = evidenceByIdentity[suggestion.identity.normalized] else {
                return suggestion
            }
            switch evidence.outcome {
            case .measuredBothPass:
                let newScore = suggestion.score + VerifyEvidenceScoring.verifyBothPassWeight
                let gatedTier = suggestion.family.tier(forScore: newScore)
                return suggestion.with(
                    score: newScore,
                    tier: gatedTier.promoted(byVerifyOutcome: .measuredBothPass),
                    whySuggested: suggestion.whySuggested
                        + ["Verify: bothPass — \(evidence.detail ?? "property held at execution")"]
                )

            case .measuredDefaultFails:
                return suggestion.with(
                    tier: .suppressed,
                    whyMightBeWrong: suggestion.whyMightBeWrong
                        + ["Verify: defaultFails — \(evidence.detail ?? "disproven by counterexample")"]
                )

            case .measuredEdgeCaseAdvisory, .measuredError, .architecturalCoveragePending:
                return suggestion
            }
        }
    }
}
