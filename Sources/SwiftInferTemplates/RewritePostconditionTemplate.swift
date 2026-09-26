import SwiftInferCore

/// The **rewrite-postcondition** law: a string-rewriting function's output lacks the tokens its own
/// body removes.
///
/// ```swift
/// static func safeAlias(_ name: String) -> String {
///     name.replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
/// }
/// ```
///
/// states `!safeAlias(s).contains("-") && !safeAlias(s).contains(" ")`; a split on `","` whose elements
/// are only trimmed or dropped states that no element contains `","`. See `RewritePostcondition`.
///
/// ## Why this law, measured before it was built
///
/// `docs/measurements/law-blind-mutants.md`: of the mutation check's 25 mutants that changed output and
/// passed their law, 3–4 are this shape — a dropped replacement, an emptied pattern, an emptied
/// separator — and each passed `idempotence` or `predicate` totality, neither of which says anything
/// about which characters come out. The ternary guard-domain law, built first from the same analysis,
/// killed both of its targets (`ternary-guard-domain.md`).
///
/// ## A characterisation law, like guard-domain
///
/// The claim is read from the body, so the code satisfies it today and it will not find a bug that
/// exists now. What it catches is an edit that drops a replacement or changes the separator.
public enum RewritePostconditionTemplate {

    public static let templateName = "rewrite-postcondition"

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            // Spelled as a literal: `StubWriterCoverageTests` finds emitted templates by this text.
            templateName: "rewrite-postcondition",
            appliesTo: Self.isStatable,
            signals: Self.signals(for:),
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "\(templateName)|" + IdempotenceTemplate.canonicalSignature(of: summary)
                )
            },
            carrier: { $0.containingTypeName },
            carrierType: { $0.parameters.first?.typeText ?? $0.containingTypeName },
            caveats: { _ in Self.makeCaveats() },
            match: { $0.bodySignals.rewritePostcondition.map(TemplateMatch.rewritePostcondition) }
        )
    }

    /// A pure, synchronous, non-throwing, non-mutating rewrite the body states a guarantee for.
    static func isStatable(_ summary: FunctionSummary) -> Bool {
        summary.bodySignals.rewritePostcondition != nil
            && !summary.isMutating && !summary.isAsync && !summary.isThrows
    }

    static func signals(for summary: FunctionSummary) -> [Signal] {
        guard let postcondition = summary.bodySignals.rewritePostcondition else { return [] }
        return [
            Signal(
                kind: .typeSymmetrySignature,
                weight: 40,
                detail: "the body states it: " + sentence(postcondition, function: summary.name)
            )
        ]
    }

    /// The law in one line, as the signal and the stub's failure label both say it.
    public static func sentence(_ postcondition: RewritePostcondition, function: String) -> String {
        let call = "\(function)(\(postcondition.parameterName))"
        switch postcondition.guarantee {
        case .outputLacks(let tokens):
            return "\(call) contains none of " + tokens.map { "\"\($0)\"" }.joined(separator: ", ")

        case .elementsLack(let separator):
            return "no element of \(call) contains \"\(separator)\""
        }
    }

    static func makeCaveats() -> [String] {
        [
            "THIS LAW CANNOT FAIL AGAINST THE CODE IT WAS READ FROM. The rewrite satisfies it by "
                + "construction, so it will not find a bug that exists today. It catches an EDIT — a "
                + "dropped replacement, a changed pattern or separator.",
            "Read the sentence and decide whether you meant it: that these characters never come out is "
                + "behaviour a caller may rely on, or an accident of today's implementation."
        ]
    }
}
