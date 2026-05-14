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
        return Suggestion(
            templateName: templateName,
            evidence: evidence,
            score: Score(signals: score.signals + [signal]),
            generator: generator,
            explainability: newExplainability,
            identity: identity,
            liftedOrigin: liftedOrigin,
            mockGenerator: mockGenerator,
            carrier: carrier
        )
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
/// `docs/calibration-cycle-63-findings.md`.
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
        evidenceByIdentity: [String: VerifyEvidence]
    ) -> [Suggestion] {
        suggestions.map { suggestion in
            guard suggestion.score.tier != .advisory,
                  let evidence = evidenceByIdentity[suggestion.identity.normalized] else {
                return suggestion
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
    }
}
