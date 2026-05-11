import SwiftInferCore

/// Monotonicity template — `f: T -> U` where `U` is `Comparable` and the
/// function name + signature shape suggest `f(x) <= f(y)` whenever
/// `x <= y` (or some user-supplied total order over `T`). PRD v0.4 §5.2.
///
/// Necessary type pattern (PRD §5.2):
///   - exactly one parameter
///   - parameter is not `inout`
///   - function is not `mutating`
///   - return type is one of the curated `Comparable` codomain types
///     (`Int`, `Double`, `Float`, `String`, `Date`, `Duration`)
///
/// Tier policy (PRD §5.2 caveat + M7 plan open decision #4): monotonicity
/// suggestions stay in the **Possible** tier by default. Without an
/// explicit `@CheckProperty(.monotonic(over:))` annotation or TestLifter
/// corroboration, the template's signal weights are sized so that even the
/// fully-fired type-pattern + curated-name combination keeps total score
/// in `20..<40`. Escalation to `.likely` lands when:
///
///   - the M5 macro extension recognises `@CheckProperty(.monotonic(over:))`
///     and adds a `+15` `discoverableAnnotation` signal, or
///   - TestLifter cross-validation contributes the `+20` `crossValidation`
///     signal (gated on TestLifter M1 — currently dormant per the M7
///     plan).
///
/// Body signal (accumulator/reduce-usage as a structural hint that the
/// function aggregates rather than summarises trivially) is reserved for
/// a follow-up; `BodySignals` doesn't carry a "this function calls reduce
/// internally" field today, and adding one expands the M1.2 scanner past
/// M7.1's scope. `accumulatorBodySignal(for:)` is wired as a `nil`-
/// returning hook so the suggest pipeline can pick it up without further
/// template-side surgery once the field lands.
public enum MonotonicityTemplate {

    /// Curated naming list per PRD §5.2 + M7.1 plan. Exact-match verbs
    /// commonly used for monotonic projections — the function name itself
    /// is a strong hint that the result grows with the input.
    public static let curatedVerbs: Set<String> = [
        "length",
        "count",
        "size",
        "priority",
        "score",
        "depth",
        "height",
        "weight"
    ]

    /// Curated suffix patterns. Functions named `userCount`, `pageSize`,
    /// `treeDepth`, etc. share the curated-verb shape modulo a noun
    /// prefix; matching the suffix lets the template fire without
    /// requiring every project to add the prefixed forms to its
    /// vocabulary.
    public static let curatedSuffixes: [String] = [
        "Count",
        "Size"
    ]

    /// Curated `Comparable` codomain types per the M7.1 plan. The plan
    /// caps at this set rather than recognising every `Comparable` type
    /// in the corpus because the template is textual (PRD §5.2): a user-
    /// declared `struct Score: Comparable` won't be matched, and that's
    /// the conservative posture the §5.2 caveat asks for. Project
    /// vocabulary doesn't currently cover codomain types — extending it
    /// is M7.1.x or later if real corpora demand it.
    public static let comparableCodomains: Set<String> = [
        "Int",
        "Double",
        "Float",
        "String",
        "Date",
        "Duration"
    ]

    /// Build a suggestion for `summary`, or return `nil` if the type
    /// pattern doesn't match or the score collapses to `.suppressed`.
    ///
    /// `vocabulary` is the project-extensible naming layer per PRD §4.5;
    /// the template consults `vocabulary.monotonicityVerbs` alongside the
    /// curated list and suffix patterns. Defaults to `.empty` so callers
    /// not yet threading vocabulary keep compiling.
    /// V1.37.A — migrated to the Constraint Engine (PRD §20.2). The
    /// template now expresses itself as a `Constraint<FunctionSummary>`
    /// via `makeConstraint(vocabulary:)`, and `suggest(for:vocabulary:)`
    /// is a thin wrapper that orchestrates the constraint through
    /// `ConstraintRunner.suggest`. Behavior preserved bit-for-bit
    /// (verified by the existing MonotonicityTemplate test suite +
    /// `MonotonicityConstraintEquivalenceTests`).
    public static func suggest(
        for summary: FunctionSummary,
        vocabulary: Vocabulary = .empty
    ) -> Suggestion? {
        ConstraintRunner.suggest(
            constraint: makeConstraint(vocabulary: vocabulary),
            subject: summary
        )
    }

    /// V1.37.A — Constraint factory. Captures `vocabulary` into the
    /// constraint's @Sendable closures. Recreated per-call (matches
    /// the pre-migration per-call behaviour); future cycles can cache.
    public static func makeConstraint(
        vocabulary: Vocabulary
    ) -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "monotonicity",
            appliesTo: { summary in
                Self.orderedCodomainSignal(for: summary) != nil
            },
            signals: { summary in
                Self.accumulatedSignals(for: summary, vocabulary: vocabulary)
            },
            evidence: { summary in
                [Self.makeEvidence(summary)]
            },
            identity: Self.makeIdentity(for:),
            carrier: { $0.containingTypeName },
            caveats: { _ in Self.makeCaveats() }
        )
    }

    /// V1.37.A — signal-accumulation order preserved from the pre-
    /// migration bespoke `suggest(for:vocabulary:)`.
    static func accumulatedSignals(
        for summary: FunctionSummary,
        vocabulary: Vocabulary
    ) -> [Signal] {
        guard let codomainSignal = orderedCodomainSignal(for: summary) else {
            return []
        }
        var signals: [Signal] = [codomainSignal]
        if let name = nameSignal(for: summary, vocabulary: vocabulary) {
            signals.append(name)
        }
        if let accumulator = accumulatorBodySignal(for: summary) {
            signals.append(accumulator)
        }
        if let veto = nonDeterministicVeto(for: summary) {
            signals.append(veto)
        }
        return signals
    }

    /// V1.37.A — caveat list for the Constraint's `caveats` closure.
    /// Constant per-suggestion (monotonicity has no input-dependent
    /// caveats, unlike Commutativity's FP advisory).
    static func makeCaveats() -> [String] {
        [
            "Ordered-codomain assumption breaks under custom Comparable conformances "
                + "that don't satisfy strict order; the curated codomain set "
                + "(Int, Double, Float, String, Date, Duration) is the only one "
                + "M7.1 recognises.",
            "Possible-tier by default per the §5.2 caveat — explicit "
                + "@CheckProperty(.monotonic(over:)) annotation escalates to Likely "
                + "(M5 macro extension is the opt-in path)."
        ]
    }

    /// Canonical hash input per PRD §7.5: `template ID | canonical
    /// signature`. Reuses `IdempotenceTemplate.canonicalSignature` so the
    /// identity rule stays consistent across single-summary templates.
    private static func makeIdentity(for summary: FunctionSummary) -> SuggestionIdentity {
        SuggestionIdentity(canonicalInput: "monotonicity|" + IdempotenceTemplate.canonicalSignature(of: summary))
    }

    // MARK: - Signals

    private static func orderedCodomainSignal(for summary: FunctionSummary) -> Signal? {
        guard summary.parameters.count == 1,
              let param = summary.parameters.first,
              !param.isInout,
              !summary.isMutating,
              let returnType = summary.returnTypeText,
              comparableCodomains.contains(returnType) else {
            return nil
        }
        return Signal(
            kind: .orderedCodomainSignature,
            weight: 25,
            detail: "Ordered-codomain signature: \(param.typeText) -> \(returnType) (Comparable)"
        )
    }

    private static func nameSignal(
        for summary: FunctionSummary,
        vocabulary: Vocabulary
    ) -> Signal? {
        // Curated exact-match takes precedence over suffix and project
        // vocabulary so a function named exactly `count` doesn't double-
        // count when the project vocabulary also lists it.
        if curatedVerbs.contains(summary.name) {
            return Signal(
                kind: .exactNameMatch,
                weight: 10,
                detail: "Curated monotonicity verb match: '\(summary.name)'"
            )
        }
        if let suffix = curatedSuffixes.first(where: { hasCuratedSuffix(summary.name, suffix: $0) }) {
            return Signal(
                kind: .exactNameMatch,
                weight: 10,
                detail: "Curated monotonicity suffix match: '\(summary.name)' (suffix '\(suffix)')"
            )
        }
        if vocabulary.monotonicityVerbs.contains(summary.name) {
            return Signal(
                kind: .exactNameMatch,
                weight: 10,
                detail: "Project-vocabulary monotonicity verb match: '\(summary.name)'"
            )
        }
        return nil
    }

    /// Reserved hook for the accumulator/reduce-usage body signal per the
    /// M7.1 plan. Returns `nil` today — `BodySignals` doesn't carry a
    /// "this function calls `.reduce` internally" field, and the existing
    /// `reducerOpsReferenced` surface tracks ops *passed to* reduce, not
    /// reduce-usage by the function itself. Wiring a real body signal
    /// requires extending `FunctionScanner`'s body-walk; that's deferred
    /// to a follow-up. The hook is kept here so the suggest pipeline
    /// picks the signal up once the scanner field exists, without
    /// reorganising the template.
    private static func accumulatorBodySignal(for summary: FunctionSummary) -> Signal? {
        _ = summary
        return nil
    }

    /// PRD §4.1's -∞ counter-signal — a function whose body calls
    /// non-deterministic APIs (`UUID()`, `Date()`, etc.) can't be
    /// reliably monotonic; the second invocation may project to a
    /// different point in the codomain regardless of input ordering.
    /// Mirrors `IdempotenceTemplate.nonDeterministicVeto`.
    private static func nonDeterministicVeto(for summary: FunctionSummary) -> Signal? {
        guard summary.bodySignals.hasNonDeterministicCall else {
            return nil
        }
        let calls = summary.bodySignals.nonDeterministicAPIsDetected.joined(separator: ", ")
        return Signal(
            kind: .nonDeterministicBody,
            weight: Signal.vetoWeight,
            detail: "Non-deterministic API in body: \(calls)"
        )
    }

    /// `true` when `name` ends with `suffix` and has at least one
    /// character of prefix before it. `"count"` does **not** match the
    /// `"Count"` suffix — the curated exact-match list handles bare
    /// `count`, and a zero-prefix match would just duplicate that path.
    /// Lowercase / mixed-case prefixes are accepted (`userCount`,
    /// `cellCount`); the suffix itself is case-sensitive.
    private static func hasCuratedSuffix(_ name: String, suffix: String) -> Bool {
        guard name.count > suffix.count, name.hasSuffix(suffix) else {
            return false
        }
        return true
    }

    // MARK: - Suggestion construction

    private static func makeEvidence(_ summary: FunctionSummary) -> Evidence {
        Evidence(
            displayName: displayName(for: summary),
            signature: signature(for: summary),
            location: summary.location
        )
    }

    private static func makeExplainability(
        for summary: FunctionSummary,
        signals: [Signal]
    ) -> ExplainabilityBlock {
        var whySuggested: [String] = []
        let evidence = makeEvidence(summary)
        whySuggested.append(
            "\(evidence.displayName) \(evidence.signature) — \(evidence.location.file):\(evidence.location.line)"
        )
        for signal in signals {
            whySuggested.append(signal.formattedLine)
        }
        let caveats: [String] = [
            "Ordered-codomain assumption breaks under custom Comparable conformances "
                + "that don't satisfy strict order; the curated codomain set "
                + "(Int, Double, Float, String, Date, Duration) is the only one "
                + "M7.1 recognises.",
            "Possible-tier by default per the §5.2 caveat — explicit "
                + "@CheckProperty(.monotonic(over:)) annotation escalates to Likely "
                + "(M5 macro extension is the opt-in path)."
        ]
        return ExplainabilityBlock(whySuggested: whySuggested, whyMightBeWrong: caveats)
    }

    // MARK: - Display helpers

    private static func displayName(for summary: FunctionSummary) -> String {
        let labels = summary.parameters.map { ($0.label ?? "_") + ":" }.joined()
        return "\(summary.name)(\(labels))"
    }

    private static func signature(for summary: FunctionSummary) -> String {
        let paramTypes = summary.parameters.map(\.typeText).joined(separator: ", ")
        var sig = "(\(paramTypes))"
        if summary.isAsync {
            sig += " async"
        }
        if summary.isThrows {
            sig += " throws"
        }
        sig += " -> \(summary.returnTypeText ?? "Void")"
        return sig
    }
}
