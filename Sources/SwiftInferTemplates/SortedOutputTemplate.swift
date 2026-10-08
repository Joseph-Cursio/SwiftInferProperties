import SwiftInferCore

/// The **sorted-output** law: a function that returns an array sorted by a tie-break comparator
/// returns it in that comparator's order (SwiftInferProperties#647).
///
/// ```swift
/// .sorted { lhs, rhs in
///     if lhs.fileCount != rhs.fileCount { return lhs.fileCount > rhs.fileCount }
///     return lhs.ruleID < rhs.ruleID
/// }
/// ```
///
/// states that adjacent elements of the result are in `(fileCount ↓, ruleID ↑)` order. The key is
/// read off the closure, so the law is the comparator restated as a check on the output.
///
/// ## Why `comparator` does not already cover it
///
/// `comparator` fires on a *named* `(T, T) -> Bool` and asks for a strict weak ordering. These
/// comparators are inline closures inside the function that returns the sorted array, so it never
/// sees them, and a tie-break chain is a lexicographic order — an SWO by construction. The claim
/// worth stating is about the **output**: it is ranked by the key the chain spells out.
///
/// ## A characterisation law, with one way to fail today
///
/// Like `guard-domain`, the law is read from the code, so it holds of the code it was read from
/// and catches an **edit**: a key dropped or reordered, a direction flipped, a condition negated.
/// Those are the edits mutation testing found surviving in exactly this shape (`ImpactReport.from`
/// in SwiftFormatRuleStudio). It can also fail against today's code, in one way: if the comparator
/// is not a strict weak ordering, `sorted(by:)` may return an array the comparator itself calls
/// unsorted — which is a defect, and the one the `comparator` template exists to find.
public enum SortedOutputTemplate {

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "sorted-output",
            appliesTo: Self.hasStatableOrdering,
            signals: Self.signals(for:),
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "sorted-output|" + IdempotenceTemplate.canonicalSignature(of: summary)
                )
            },
            carrier: { $0.containingTypeName },
            carrierType: { $0.parameters.first?.typeText ?? $0.containingTypeName },
            caveats: { _ in Self.makeCaveats() },
            // The same `SortedOutput` the signal renders into prose, carried as data for the writer.
            match: { $0.bodySignals.sortedOutput.map(TemplateMatch.sortedOutput) }
        )
    }

    /// A synchronous, non-throwing, non-mutating function whose body returns a sorted array in a
    /// shape `SortedOutputReader` could restate. `throws` and `async` are excluded as
    /// `guard-domain` excludes them: the law is a check on one returned value, and a failure to
    /// return is an outcome it does not describe.
    static func hasStatableOrdering(_ summary: FunctionSummary) -> Bool {
        summary.bodySignals.sortedOutput != nil
            && !summary.isMutating
            && !summary.isAsync
            && !summary.isThrows
    }

    static func signals(for summary: FunctionSummary) -> [Signal] {
        guard let ordering = summary.bodySignals.sortedOutput else { return [] }
        let subject = ordering.member.map { "\(summary.name)(…).\($0)" } ?? "\(summary.name)(…)"
        var signals = [
            Signal(
                kind: .typeSymmetrySignature,
                weight: 40,
                detail: "the body sorts it: \(subject) is ordered by \(describe(ordering.keys))"
            )
        ]
        if let doc = summary.docComment, statesAnOrdering(doc) {
            signals.append(Signal(
                kind: .docstringCorroboration,
                weight: 20,
                detail: "The doc comment says the result is ordered"
            ))
        }
        return signals
    }

    /// `(fileCount ↓, findingCount ↓, ruleID ↑)`.
    static func describe(_ keys: [SortKey]) -> String {
        "(" + keys.map { "\($0.path) \($0.ascending ? "↑" : "↓")" }.joined(separator: ", ") + ")"
    }

    /// Whether a doc comment calls the result ordered. Word-start matches over lowercased prose,
    /// the same reading `DocstringAdvisor.isContract` gives its cues.
    static func statesAnOrdering(_ doc: String) -> Bool {
        let prose = doc.lowercased()
        return ["sorted", "ranked", "ordered", "in order"].contains { cue in
            prose.range(of: "\\b" + cue, options: .regularExpression) != nil
        }
    }

    static func makeCaveats() -> [String] {
        [
            "THIS LAW IS THE COMPARATOR, RESTATED. The result is sorted by it, so the law holds of "
                + "the code it was read from and catches an EDIT — a key dropped or reordered, a "
                + "direction flipped, a tie-break negated.",
            "IT CAN FAIL TODAY IN ONE WAY: a comparator that is not a strict weak ordering lets "
                + "`sorted(by:)` return an array the comparator itself calls unsorted. That failure "
                + "is a real defect in the comparator, not in the law.",
            "IT DOES NOT SAY WHAT IS IN THE ARRAY — only its order. A result that drops or "
                + "duplicates elements, or ranks the wrong thing, passes.",
            "A GENERATOR OF DISTINCT VALUES MISSES A DROPPED OR REORDERED KEY. Keys only disagree "
                + "when elements share values — two findings in one rule, one rule in several files "
                + "— and a wide alphabet almost never draws that. Narrow the alphabet of whatever "
                + "the result is grouped or keyed by: on `ImpactReport.from`, a dropped key passed "
                + "100 trials at the default generator and failed with three values per key."
        ]
    }
}

extension TemplateRegistry {

    /// `SortedOutputTemplate`. A separate collector, reached from `collectValueLawSuggestions`,
    /// because `TemplateRegistry+Collection`'s collecting function is at its length cap.
    static func collectSortedOutputSuggestions(
        summaries: [FunctionSummary],
        into collector: inout SuggestionCollector
    ) {
        for summary in summaries {
            if let suggestion = SortedOutputTemplate.suggest(for: summary) {
                collector.record(
                    suggestion,
                    generatorType: summary.parameters.first?.typeText ?? summary.containingTypeName
                )
            }
        }
    }
}
