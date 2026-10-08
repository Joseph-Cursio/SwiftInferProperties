import SwiftInferCore

/// A function selecting what lies in a range given by `from:` and `to:` — and the law that the
/// empty range selects nothing: `f(from: v, to: v).isEmpty`.
///
/// ## Why this template exists
///
/// Measured on SwiftLintRuleStudioCore's `SwiftLintDeprecations.rulesAdded(from:to:)`, which
/// collects the rules added in versions after `from` up to `to`:
///
/// ```swift
/// if isVersion(fromVersion, lessThan: version) && !isVersion(toVersion, lessThan: version) { … }
/// ```
///
/// Its `&&` → `||` mutant selects every version, and survived. The law that catches it is the
/// boundary every range owes: from a point to the same point there is nothing. Composition —
/// `f(a, c) ⊆ f(a, b) ∪ f(b, c)` — was considered and rejected: it holds for every interval
/// *and* for the mutant, which selects nearly everything on both sides.
///
/// ## Entailed by Swift's convention
///
/// `to:` is exclusive in Swift — `stride(from:to:by:)` stops before it, and the inclusive form is
/// spelled `through:`. Whether `from` is inclusive or not, `[v, v)` and `(v, v]` are both empty,
/// so the law follows from the label. A function that spells an inclusive end `to:` fails it
/// correctly: that is the convention the reader of the call site relies on. `through:` is not read.
///
/// ## Scope
///
/// Two parameters labelled exactly `from` and `to`, of one type, returning a collection. Only free
/// and static functions: an instance method would need a receiver drawn as well, and no measured
/// case was one.
public enum EmptyRangeTemplate {

    public static let templateName = "empty-range"

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "empty-range",
            appliesTo: Self.isRangeSelection,
            signals: Self.signals(for:),
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "empty-range|" + IdempotenceTemplate.canonicalSignature(of: summary)
                )
            },
            carrier: { $0.containingTypeName },
            carrierType: { $0.parameters.first?.typeText },
            caveats: { _ in Self.makeCaveats() }
        )
    }

    static func isRangeSelection(_ summary: FunctionSummary) -> Bool {
        guard summary.parameters.count == 2,
              summary.parameters[0].label == "from", summary.parameters[1].label == "to",
              summary.parameters[0].typeText == summary.parameters[1].typeText,
              !summary.parameters[0].isInout, !summary.parameters[1].isInout,
              !summary.isMutating, !summary.isAsync, !summary.isThrows,
              summary.containingTypeName == nil || summary.isStatic,
              let returnType = summary.returnTypeText else { return false }
        return isCollection(returnType)
    }

    static func isCollection(_ typeText: String) -> Bool {
        (typeText.hasPrefix("[") && typeText.hasSuffix("]"))
            || ["Set<", "Array<", "ContiguousArray<", "ArraySlice<"].contains { typeText.hasPrefix($0) }
    }

    static func signals(for summary: FunctionSummary) -> [Signal] {
        guard isRangeSelection(summary), let returnType = summary.returnTypeText else { return [] }
        let bound = summary.parameters[0].typeText
        return [
            Signal(
                kind: .typeSymmetrySignature,
                weight: 30,
                detail: "Range selection: (from: \(bound), to: \(bound)) -> \(returnType)"
            ),
            Signal(
                kind: .exactNameMatch,
                weight: 15,
                detail: "Labelled `from:` / `to:` — Swift's exclusive end, so `\(summary.name)(from: v, "
                    + "to: v)` selects nothing"
            )
        ]
    }

    static func makeCaveats() -> [String] {
        [
            "THE LAW IS `f(from: v, to: v).isEmpty` — a range from a point to itself holds nothing. "
                + "It is refutable where the bounds are combined wrongly: a `&&` written `||` selects "
                + "nearly everything, an inclusive comparison on both ends selects `v` itself.",
            "`to:` IS EXCLUSIVE BY SWIFT'S CONVENTION (`stride(from:to:by:)`; the inclusive form is "
                + "`through:`). If this function means an inclusive end, the law fails correctly — "
                + "rename the label to `through:` rather than suppressing the law."
        ]
    }
}

extension TemplateRegistry {

    /// The laws over one value's members or one result: emptiness agreement, the two range laws,
    /// and the order of a sorted result. One call from `TemplateRegistry+Collection`, whose
    /// collecting function is at its length cap.
    static func collectValueLawSuggestions(
        summaries: [FunctionSummary],
        into collector: inout SuggestionCollector
    ) {
        collectEmptinessAgreementSuggestions(summaries: summaries, into: &collector)
        collectRangeLawSuggestions(summaries: summaries, into: &collector)
        collectSortedOutputSuggestions(summaries: summaries, into: &collector)
    }

    /// The two range laws — `EmptyRangeTemplate` and `DocumentedRangeTemplate`. Lives here rather
    /// than in `TemplateRegistry+Collection`, which is at its length cap.
    static func collectRangeLawSuggestions(
        summaries: [FunctionSummary],
        into collector: inout SuggestionCollector
    ) {
        for summary in summaries {
            if let suggestion = EmptyRangeTemplate.suggest(for: summary) {
                collector.record(suggestion, generatorType: summary.parameters.first?.typeText)
            }
            if let suggestion = DocumentedRangeTemplate.suggest(for: summary) {
                collector.record(
                    suggestion,
                    generatorType: summary.parameters.first?.typeText ?? summary.containingTypeName
                )
            }
        }
    }
}
