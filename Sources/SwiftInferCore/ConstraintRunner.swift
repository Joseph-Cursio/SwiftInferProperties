/// V1.36.B — Constraint Engine runner (PRD §20.2 foundation).
///
/// Orchestrates a `Constraint<Subject>` against a specific subject to
/// produce a `Suggestion?`. The runner is the single seam between the
/// constraint-as-data layer (V1.36.A) and the existing `Suggestion`
/// downstream contract.
///
/// **Returns `nil` in two cases**:
///   1. `constraint.appliesTo(subject)` returns `false` — the gate
///      rejects the subject before any signal work.
///   2. The accumulated `Score(signals:)` lands in `.suppressed`
///      tier — a veto fired OR the signal sum is below the §4.2
///      threshold (`< 20`).
///
/// **Pure function.** Same `(constraint, subject)` always produces
/// the same `Suggestion?`. Side-effect-free; thread-safe by
/// construction. The constraint's closures are `@Sendable` so the
/// runner can be invoked concurrently from multiple actors.
///
/// **Explainability synthesis.** The runner builds the
/// `ExplainabilityBlock.whySuggested` list from evidence display +
/// signal-formatted-lines, and `whyMightBeWrong` from
/// `constraint.caveats(subject)`. This mirrors what every existing
/// bespoke template does, so the v1.36.C migration produces bit-for-
/// bit-equivalent output without per-template explainability
/// duplication.
public enum ConstraintRunner {

    /// Build a `Suggestion` from a `Constraint<Subject>` applied to
    /// `subject`. See type-level docs for the two `nil`-return cases.
    public static func suggest<Subject>(
        constraint: Constraint<Subject>,
        subject: Subject
    ) -> Suggestion? {
        guard constraint.appliesTo(subject) else { return nil }
        let signals = constraint.signals(subject)
        let score = Score(signals: signals)
        guard score.tier != .suppressed else { return nil }
        let evidence = constraint.evidence(subject)
        let explainability = makeExplainability(
            evidence: evidence,
            additionalWhySuggested: constraint.additionalWhySuggested(subject),
            signals: signals,
            caveats: constraint.caveats(subject)
        )
        return Suggestion(
            templateName: constraint.templateName,
            evidence: evidence,
            score: score,
            generator: .m1Placeholder,
            explainability: explainability,
            identity: constraint.identity(subject),
            carrier: constraint.carrier(subject),
            carrierTypeName: constraint.carrierType(subject)
        )
    }

    /// V1.36.B — default explainability assembly. Mirrors the shape
    /// every existing template's `makeExplainability(...)` produces:
    ///
    /// `whySuggested` =
    ///   - one line per evidence row, formatted as
    ///     `"<displayName> <signature> — <file>:<line>"`
    ///   - one line per signal via `Signal.formattedLine`
    ///
    /// `whyMightBeWrong` = the constraint's caveats list verbatim.
    ///
    /// Module-internal so the V1.36.B unit tests can verify the
    /// rendering shape without going through `suggest(...)`.
    /// V1.39 — extended with `additionalWhySuggested` for templates
    /// (e.g. `IdempotenceTemplate+Lifted`) that insert a per-suggestion
    /// narrative between the evidence-display lines and the signal
    /// lines. Defaults to empty for templates whose evidence + signals
    /// are self-documenting.
    static func makeExplainability(
        evidence: [Evidence],
        additionalWhySuggested: [String] = [],
        signals: [Signal],
        caveats: [String]
    ) -> ExplainabilityBlock {
        var whySuggested: [String] = []
        for row in evidence {
            whySuggested.append(
                "\(row.displayName) \(row.signature) — "
                    + "\(row.location.file):\(row.location.line)"
            )
        }
        whySuggested.append(contentsOf: additionalWhySuggested)
        for signal in signals {
            whySuggested.append(signal.formattedLine)
        }
        return ExplainabilityBlock(
            whySuggested: whySuggested,
            whyMightBeWrong: caveats
        )
    }
}
