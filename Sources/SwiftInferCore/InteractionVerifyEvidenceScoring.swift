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
///   biconditional) the gate pins `.possible` — **except** when a measured
///   bothPass is established at **full action-space coverage**
///   (`excludedActionCount == 0`): the cycle-135 pin-overrule then promotes
///   via the ungated tier (30 + 50 = 80 → `.strong` → `.verified`) and
///   discloses the overrule. A *partial* bothPass (or legacy `nil`
///   coverage) keeps the `.possible` pin — the family's failure mode lives
///   in the excluded composition actions, so partial coverage is biased
///   toward false-pass (cycle 135).
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
                return gradedForBothPass(suggestion, evidence: evidence)

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

    /// The `measuredBothPass` arm, extracted (keeps the `applied` closure
    /// under SwiftLint's `closure_body_length` cap). Adds the +50 weight,
    /// then resolves the tier through the Finding-G gate **with the cycle-135
    /// full-coverage pin-overrule**: a gated family (cardinality /
    /// biconditional) is normally clamped to `.possible` by
    /// `tier(forScore:)`, but a measured `bothPass` at **full action-space
    /// coverage** (`excludedActionCount == 0`) is sound per-candidate proof
    /// the reducer enforces the invariant itself, so it overrules the pin and
    /// promotes via the *ungated* tier. A partial bothPass (or legacy `nil`
    /// coverage) keeps the clamp — the failure mode lives in the excluded
    /// composition actions, so partial coverage is biased toward false-pass.
    /// Static score alone never overrules (this path is measured-evidence
    /// only). Non-gated families are unaffected (`gatedTier == ungatedTier`).
    private static func gradedForBothPass(
        _ suggestion: InteractionInvariantSuggestion,
        evidence: VerifyEvidence
    ) -> InteractionInvariantSuggestion {
        let newScore = suggestion.score + VerifyEvidenceScoring.verifyBothPassWeight
        let gatedTier = suggestion.family.tier(forScore: newScore)
        let overruled = suggestion.family.swiftProjectLintDeferral != nil
            && evidence.excludedActionCount == 0
        let effectiveTier = overruled ? Tier(score: newScore) : gatedTier
        let note = "Verify: bothPass — " + (evidence.detail ?? "property held at execution")
            + (overruled
                ? " (Finding-G pin overruled by full-coverage measured execution — 0 excluded actions)"
                : "")
        return suggestion.with(
            score: newScore,
            tier: effectiveTier.promoted(byVerifyOutcome: .measuredBothPass),
            whySuggested: suggestion.whySuggested + [note]
        )
    }
}
