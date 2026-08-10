import Foundation

extension Suggestion {

    /// Which explainability arm a folded-in signal's `formattedLine`
    /// joins — V1.66.
    enum ExplainabilityArm {
        case whySuggested
        case whyMightBeWrong
    }

    /// V1.66 — return a copy with `signal` appended to the score and its
    /// `formattedLine` appended to the named explainability arm. The
    /// `Score` is rebuilt via `Score(signals:)`, so a veto signal
    /// collapses the tier to `.suppressed` and a positive signal raises
    /// the total (and may lift the tier).
    func appendingScoreSignal(
        _ signal: Signal,
        explainabilityArm arm: ExplainabilityArm
    ) -> Suggestion {
        let newExplainability: ExplainabilityBlock
        switch arm {
        case .whySuggested:
            newExplainability = ExplainabilityBlock(
                whySuggested: explainability.whySuggested + [signal.formattedLine],
                whyMightBeWrong: explainability.whyMightBeWrong
            )

        case .whyMightBeWrong:
            newExplainability = ExplainabilityBlock(
                whySuggested: explainability.whySuggested,
                whyMightBeWrong: explainability.whyMightBeWrong + [signal.formattedLine]
            )
        }
        // Mutate a copy. The field-by-field rebuild this replaces silently dropped BOTH
        // `carrierTypeName` and `generatorRecipes` — the omitted arguments have defaults, so the
        // compiler said nothing and the suggestion rendered fine with half of itself missing.
        return withAdditionalSignal(signal, explainability: newExplainability)
    }
}

/// V1.66 — verify-as-signal post-pass: folds persisted `swift-infer
/// verify` outcomes into suggestion `Score`s so verify evidence
/// participates in the grade, not just the rendered annotation.
///
/// - `.measuredBothPass` → a heavy positive `verifyBothPass` signal
///   (`+verifyBothPassWeight`); the score rises and the tier may lift.
/// - `.measuredDefaultFails` → a `verifyDisproven` veto signal; the
///   suggestion collapses to `.suppressed` and discover drops it.
///
/// **This overturns the cycle-61/62 "defaultFails does not demote"
/// decision** — deliberately. That decision rested on PRD §3.5's
/// conservatism toward *heuristic* inference (the Daikon trap: too many
/// speculative guesses). A `defaultFails` outcome is not a heuristic
/// guess — it is an *executed counterexample*. The property was run and
/// mathematically failed. Suppressing a disproven suggestion raises
/// precision; surfacing it would be a true false positive. See
/// `git show 31a347a:docs/calibration-cycle-63-findings.md`.
///
/// `.measuredEdgeCaseAdvisory` is left score-neutral — it holds for the
/// default domain and is genuinely ambiguous; v1.64.C already annotates
/// it. `.measuredError` / `.architecturalCoveragePending` are not
/// verdicts and are score-neutral. `.advisory`-tier suggestions are
/// skipped entirely — they carry no runnable property, so verify
/// evidence should not reshape them (and a rebuild would lose the
/// explicit `.advisory` tier).
///
/// Pure and order-preserving — a post-pass over a built `[Suggestion]`,
/// applied by the discover CLI path once `verify-evidence.json` is
/// loaded. The `Score` pipeline runs before evidence is available, so
/// the signal joins via rebuild rather than at score-construction time.
public enum VerifyEvidenceScoring {

    /// Weight of the `verifyBothPass` signal. Heavier than any single
    /// heuristic signal (the largest of those is +40–50): an executed,
    /// passed property is the strongest single piece of evidence the
    /// system can hold. +50 lifts even a bare exact-name-match pick
    /// (+40 → Likely) past the Strong threshold (75).
    public static let verifyBothPassWeight = 50

    /// Fold `evidenceByIdentity` into `suggestions`. Order is preserved;
    /// suggestions with no evidence, a score-neutral outcome, or the
    /// `.advisory` tier pass through unchanged (identical value, so
    /// callers can rely on `==`).
    public static func applied(
        to suggestions: [Suggestion],
        evidenceByIdentity: [String: VerifyEvidence],
        currentFingerprintByIdentity: [String: String]
    ) -> [Suggestion] {
        suggestions.map { suggestion in
            guard suggestion.score.tier != .advisory,
                  let evidence = evidenceByIdentity[suggestion.identity.normalized] else {
                return suggestion
            }
            return graded(
                suggestion,
                with: evidence,
                currentFingerprint: currentFingerprintByIdentity[suggestion.identity.normalized]
            )
        }
    }

    /// The subset of `evidenceByIdentity` that is actually about the code in front of the
    /// reader — the same rule `applied` scores by, exposed so RENDERING cannot disagree with
    /// scoring.
    ///
    /// **It had to be exposed because the two did disagree.** `SuggestionRenderer.render`
    /// computes the displayed tier as `score.tier.promoted(byVerifyOutcome:)` — `.verified` is
    /// set by the surfacing pipeline rather than derived from the score (`Tier`) — and it was
    /// handed the RAW map. So a row whose `+50` had been correctly withheld still printed
    /// `Verified`, directly above its own caveat saying the evidence was not being applied.
    /// Measured on this repo the day the staleness gate shipped: 4 such rows on
    /// `SwiftInferCore`.
    ///
    /// One rule, one place: filter here, and every consumer inherits the decision.
    public static func applicable(
        evidenceByIdentity: [String: VerifyEvidence],
        currentFingerprintByIdentity: [String: String]
    ) -> [String: VerifyEvidence] {
        evidenceByIdentity.filter { identity, evidence in
            stalenessCaveat(evidence: evidence, current: currentFingerprintByIdentity[identity]) == nil
        }
    }

    /// Fold one piece of evidence into one suggestion.
    ///
    /// Split out of `applied`'s closure for SwiftLint's 30-line closure cap once the
    /// staleness gate joined it.
    private static func graded(
        _ suggestion: Suggestion,
        with evidence: VerifyEvidence,
        currentFingerprint: String?
    ) -> Suggestion {
        // Evidence is only about the code it was measured on. `identityHash` cannot
        // establish that — it is deliberately blind to the body (PRD §7.5) — so the
        // fingerprint is what licenses USING this outcome at all.
        if let staleness = stalenessCaveat(evidence: evidence, current: currentFingerprint) {
            return suggestion.appendingScoreSignal(
                Signal(kind: .verifyEvidenceStale, weight: 0, detail: staleness),
                explainabilityArm: .whyMightBeWrong
            )
        }
        switch evidence.outcome {
        case .measuredBothPass:
            return suggestion.appendingScoreSignal(
                Signal(
                    kind: .verifyBothPass,
                    weight: verifyBothPassWeight,
                    detail: "Verify: bothPass — \(evidence.detail ?? "property held at execution")"
                ),
                explainabilityArm: .whySuggested
            )

        case .measuredDefaultFails:
            return suggestion.appendingScoreSignal(
                Signal(
                    kind: .verifyDisproven,
                    weight: Signal.vetoWeight,
                    detail: "Verify: defaultFails — \(evidence.detail ?? "disproven by counterexample")"
                ),
                explainabilityArm: .whyMightBeWrong
            )

        case .measuredEdgeCaseAdvisory, .measuredError, .architecturalCoveragePending:
            return suggestion
        }
    }

    /// Why this evidence may not be used, or `nil` when it is valid for the code in front of
    /// the reader.
    ///
    /// **Applied to promotions and vetoes alike, deliberately.** The premise is *evidence
    /// taken against a different body is not evidence about this body*; honouring that in one
    /// direction only would be incoherent. A stale `defaultFails` therefore stops suppressing
    /// — but the caveat still names the refutation, so the warning survives even though the
    /// score effect does not.
    ///
    /// **A missing fingerprint is treated as unvalidatable, not as valid.** That is the
    /// deliberate cost of the fix: every record written before this shipped stops promoting
    /// until re-verified. Trusting them instead would preserve exactly the defect being
    /// closed, on exactly the records known to be stale.
    static func stalenessCaveat(evidence: VerifyEvidence, current: String?) -> String? {
        let captured = ISO8601DateFormatter().string(from: evidence.capturedAt)
        guard let recorded = evidence.subjectFingerprint else {
            return "Verify evidence from \(captured) is NOT being applied: it was recorded "
                + "before swift-infer stamped runs with the subject's body, so there is no way "
                + "to tell whether it was measured on the code above. Re-run `swift-infer "
                + "verify` for this pick to restore it."
        }
        guard let current else {
            return "Verify evidence from \(captured) is NOT being applied: this run could not "
                + "fingerprint the subject's body (a declaration with no body, or a subject "
                + "the scan did not reach), so the evidence cannot be matched to it."
        }
        guard recorded != current else { return nil }
        return "Verify evidence from \(captured) is NOT being applied: it was measured against "
            + "a DIFFERENT version of this function's body (recorded \(recorded), now "
            + "\(current)). The law may no longer hold — re-run `swift-infer verify`."
    }
}
