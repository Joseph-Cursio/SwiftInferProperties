import SwiftInferCore

/// The **guard-domain** law: on the sub-domain a function's own early return carves out, the
/// answer is the expression that return names.
///
/// ```swift
/// guard source.hasPrefix("---") else { return (Self(), source) }
/// ```
///
/// states `!s.hasPrefix("---") ⟹ parse(from: s) == (FrontMatter(), s)`, and that sentence was
/// written by hand as a predicted law for this exact function before any tool ran — then not
/// proposed. See `docs/measurements/s3-characterisation.md`.
///
/// ## Why this is the first body-derived template
///
/// Every other template reads a **signature**. Classifying the 21 laws the walk predicted and
/// the catalog missed: **15 are facts about bodies and 2 about signatures.** S3 is not that the
/// catalog is small; it is that the catalog was looking at the wrong half of the declaration.
///
/// ## Role-entailed, and for a different reason from every other member of that set
///
/// `comparator` owes a strict weak ordering *by virtue of being one*. This owes its law because
/// **the code is the law's source**: the claim is read from the guard, not inferred from a name,
/// so a correct implementation cannot fail it. That is the opposite end of the same axis
/// `idempotence` sits on — a naming conjecture that a correct `T -> T` can fail, which is why
/// both of this walk's running laws were false alarms.
///
/// ## And it cannot find a bug that exists today — which is stated in its own caveat
///
/// The guard satisfies the law by construction. What the law catches is an **edit**: a refactor
/// that drops the guard, reorders it after a mutation, or normalises the value it used to return
/// untouched. That is a characterisation test. It is worth emitting because nothing else in this
/// tool protects deliberate sub-domain behaviour, and because a reader can tell at a glance
/// whether the sentence is one they meant — it is their own line, read back to them.
///
/// Measured across 5 952 functions in four repositories: **69 sites**, 9 of which return an
/// expression mentioning the parameter (the identity family, `parse` among them) and 60 a
/// constant.
public enum GuardDomainTemplate {

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "guard-domain",
            appliesTo: Self.hasStatableDomain,
            signals: Self.signals(for:),
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "guard-domain|"
                        + IdempotenceTemplate.canonicalSignature(of: summary)
                )
            },
            carrier: { $0.containingTypeName },
            carrierType: { $0.parameters.first?.typeText ?? $0.containingTypeName },
            caveats: { _ in Self.makeCaveats() },
            // #477 — the same `GuardDomain` the signal renders into prose, carried as data. The
            // signal is built from this value, so the two cannot disagree.
            match: { $0.bodySignals.guardDomain.map(TemplateMatch.guardDomain) }
        )
    }

    /// A pure, synchronous, non-mutating function returning a value, whose first statement
    /// carves out a sub-domain a caller can evaluate.
    ///
    /// `throws` is excluded rather than tolerated: the law compares `f(x)` to an expression, and
    /// a throwing call needs a `try` whose failure is a third outcome the law does not describe.
    static func hasStatableDomain(_ summary: FunctionSummary) -> Bool {
        guard summary.bodySignals.guardDomain != nil,
              !summary.isMutating,
              !summary.isAsync,
              !summary.isThrows,
              let returnType = summary.returnTypeText,
              returnType != "Void", returnType != "()" else {
            return false
        }
        return true
    }

    static func signals(for summary: FunctionSummary) -> [Signal] {
        guard let domain = summary.bodySignals.guardDomain else { return [] }
        let arrow = domain.firesWhenConditionHolds ? "" : "!"
        return [
            Signal(
                kind: .typeSymmetrySignature,
                weight: 40,
                detail: "the body states it: \(arrow)(\(domain.condition)) ⟹ "
                    + "\(summary.name)(\(domain.parameterName)) == \(domain.returnedExpression)"
            )
        ]
    }

    static func makeCaveats() -> [String] {
        [
            "THIS LAW CANNOT FAIL AGAINST THE CODE IT WAS READ FROM. The guard satisfies it by "
                + "construction, so it will not find a bug that exists today. It catches an EDIT "
                + "— a refactor that drops the guard, reorders it after a mutation, or normalises "
                + "the value it used to return untouched.",
            "Read the sentence and decide whether you meant it. It is your own line played back, "
                + "so the question is not whether the code satisfies it — it does — but whether "
                + "the sub-domain it names is behaviour you intend to keep."
        ]
    }
}
