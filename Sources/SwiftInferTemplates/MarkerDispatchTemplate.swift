import SwiftInferCore

/// The **marker-dispatch** law: a `String -> E` function written as a keyword table dispatches
/// every marker to its row's case (SwiftInferProperties#644).
///
/// ```swift
/// let lower = ruleName.lowercased()
/// if lower.contains("comment") || lower.contains("doc") { return .comments }
/// if lower.contains("sort") || lower.contains("mark") { return .organization }
/// return .idiomatic
/// ```
///
/// The `(marker, case)` pairs and their precedence are read off the syntax, so — like
/// `caseiterable-key-injectivity` — the domain is finite and the stub checks it exhaustively,
/// with no generator: each marker bare, inside affixes that spell no marker, and in upper case when
/// the chain reads a `lowercased()` binding.
///
/// ## Why the example test missed it
///
/// Six `||` → `&&` mutants survived in SwiftFormatRuleStudio's `heuristicCategory`: the example
/// test reached every *branch* through one keyword each, and a `&&` only changes the answer for a
/// name holding one keyword of the disjunction but not the others. Checking every marker alone is
/// what reaches that.
///
/// ## Three things a correct stub has to get right
///
/// 1. **Precedence.** A row is checked only through a name that dispatches to it: a marker an
///    earlier row claims (its literal contains an earlier one, or starts with an earlier prefix) is
///    reported, not checked — otherwise the law would be false as stated.
/// 2. **Affixes that spell nothing.** Affix letters appear in no marker, so they cannot complete an
///    earlier one across the boundary.
/// 3. **A front table.** When the chain is reached through `primary(for: x) ?? chain(for: x)`, the
///    stub calls the front and skips names the lookup claims — and fails if it claims all of them,
///    rather than passing on nothing.
public enum MarkerDispatchTemplate {

    public static func suggest(for subject: MarkerDispatchSubject) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: subject)
    }

    public static func makeConstraint() -> Constraint<MarkerDispatchSubject> {
        Constraint<MarkerDispatchSubject>(
            templateName: "marker-dispatch",
            appliesTo: { !$0.dispatch.probes().checkable.isEmpty },
            signals: Self.signals(for:),
            evidence: { [$0.entry.inferenceEvidence] },
            identity: { subject in
                SuggestionIdentity(
                    canonicalInput: "marker-dispatch|" + IdempotenceTemplate.canonicalSignature(of: subject.entry)
                )
            },
            carrier: { $0.entry.containingTypeName },
            carrierType: { $0.entry.containingTypeName },
            caveats: Self.makeCaveats(for:),
            match: Self.match(for:)
        )
    }

    /// The table, its front, and the result type the stub's table is typed with.
    static func match(for subject: MarkerDispatchSubject) -> TemplateMatch? {
        guard let resultType = subject.entry.returnTypeText else { return nil }
        return .markerDispatch(
            MarkerDispatchMatch(dispatch: subject.dispatch, front: subject.front, resultType: resultType)
        )
    }

    static func signals(for subject: MarkerDispatchSubject) -> [Signal] {
        let cases = Set(subject.dispatch.rows.map(\.result)).count
        var detail = "the body dispatches \(subject.dispatch.rows.count) markers to \(cases) cases, first match wins"
        if subject.entry.name != subject.chain.name {
            detail += ", reached through \(subject.entry.name)(…)"
        }
        return [Signal(kind: .typeSymmetrySignature, weight: 40, detail: detail)]
    }

    static func makeCaveats(for subject: MarkerDispatchSubject) -> [String] {
        var caveats = [
            "THIS LAW IS THE KEYWORD TABLE, RESTATED. Every marker is checked alone, so it catches an "
                + "EDIT — a `||` turned `&&`, a marker dropped or misspelled, two rows reordered — and "
                + "it holds of the code it was read from.",
            "IT SAYS NOTHING ABOUT A NAME WITH NO MARKER: those fall through to the last return, "
                + "which this law does not check."
        ]
        let shadowed = subject.dispatch.probes().shadowed
        if !shadowed.isEmpty {
            caveats.append(
                "\(shadowed.count) MARKER(S) CANNOT BE CHECKED — an earlier row claims them: "
                    + shadowed.map { "\"\($0)\"" }.joined(separator: ", ")
                    + ". That is precedence working, or a marker no input can ever reach."
            )
        }
        if let front = subject.front {
            caveats.append(
                "REACHED THROUGH `\(subject.entry.name)`, which asks `\(front.primaryName)` first. Names "
                    + "that lookup answers are skipped, and the test fails if it answers every one."
            )
        }
        return caveats
    }
}

/// A dispatch chain and the function a test calls to reach it — the chain itself, or the front
/// that consults a lookup first.
public struct MarkerDispatchSubject: Sendable, Equatable {
    public let chain: FunctionSummary
    public let entry: FunctionSummary
    public let dispatch: MarkerDispatch
    public let front: FallbackDelegation?

    public init(chain: FunctionSummary, entry: FunctionSummary, dispatch: MarkerDispatch, front: FallbackDelegation?) {
        self.chain = chain
        self.entry = entry
        self.dispatch = dispatch
        self.front = front
    }

    /// Every chain a test can call without a receiver, entered through its front when a sibling
    /// on the same type is `primary(for: x) ?? chain(for: x)`.
    ///
    /// Instance methods are declined: the table is a function of its argument, and drawing a
    /// receiver to reach it would make the stub depend on state the law does not mention.
    public static func candidates(in summaries: [FunctionSummary]) -> [Self] {
        summaries.compactMap { chain in
            guard let dispatch = chain.bodySignals.markerDispatch,
                  isCallableWithoutReceiver(chain),
                  !chain.isAsync, !chain.isThrows, !chain.isMutating else {
                return nil
            }
            let front = summaries.first { candidate in
                candidate.containingTypeName == chain.containingTypeName
                    && candidate.bodySignals.fallbackDelegation?.fallbackName == chain.name
                    && candidate.returnTypeText == chain.returnTypeText
                    && isCallableWithoutReceiver(candidate)
            }
            return Self(
                chain: chain,
                entry: front ?? chain,
                dispatch: dispatch,
                front: front?.bodySignals.fallbackDelegation
            )
        }
    }

    private static func isCallableWithoutReceiver(_ summary: FunctionSummary) -> Bool {
        summary.isStatic || summary.containingTypeName == nil
    }
}

extension TemplateRegistry {

    /// `MarkerDispatchTemplate`. Reached from `collectValueLawSuggestions`, because
    /// `TemplateRegistry+Collection`'s collecting function is at its length cap.
    static func collectMarkerDispatchSuggestions(
        summaries: [FunctionSummary],
        into collector: inout SuggestionCollector
    ) {
        for subject in MarkerDispatchSubject.candidates(in: summaries) {
            if let suggestion = MarkerDispatchTemplate.suggest(for: subject) {
                collector.record(suggestion, generatorType: "String")
            }
        }
    }
}
