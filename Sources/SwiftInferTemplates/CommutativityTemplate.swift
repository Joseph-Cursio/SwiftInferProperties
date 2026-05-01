import SwiftInferCore

/// Commutativity template — `f: (T, T) -> T` where applying `f` to two
/// arguments in either order yields the same result. Single-function
/// template (no cross-function pairing); scoring drawn from PRD v0.3
/// §4 + §5.2.
///
/// Necessary type pattern (PRD §5.2):
///   - exactly two parameters
///   - neither parameter is `inout`
///   - both parameter types match each other
///   - return type matches the parameter type
///   - function is not `mutating`
///   - return type is not `Void` / `()`
///
/// If the pattern doesn't hold, the template returns `nil`. If the
/// pattern holds but the score collapses to `.suppressed` (veto, or
/// anti-commutativity counter-signal lands the total below 40), the
/// template still returns `nil`.
public enum CommutativityTemplate {

    /// Curated commutativity-verb list per PRD v0.3 §4 / §5.2. Project
    /// vocabulary entries (`commutativityVerbs` from `vocabulary.json`)
    /// are consulted alongside this list at the same +40 weight per
    /// PRD §4.5; curated takes precedence so a project repeating a
    /// curated entry never double-fires.
    public static let curatedVerbs: Set<String> = [
        "add",
        "combine",
        "merge",
        "union",
        "intersect"
    ]

    /// Curated anti-commutativity-verb list per PRD v0.3 §4.1's -30
    /// counter-signal row. Function names that strongly suggest
    /// ordered/asymmetric semantics — they're typically not commutative
    /// even when the type pattern holds. Combined with the +30
    /// type-symmetry signal, a -30 hit lands the total at 0 → `.suppressed`.
    public static let curatedAntiCommutativityVerbs: Set<String> = [
        "subtract",
        "difference",
        "divide",
        "apply",
        "prepend",
        "append",
        "concat",
        "concatenate",
        "concatenated"
    ]

    /// Build a suggestion for `summary`, or return `nil` if the type
    /// pattern doesn't match or the score collapses to `.suppressed`.
    public static func suggest(
        for summary: FunctionSummary,
        vocabulary: Vocabulary = .empty
    ) -> Suggestion? {
        guard let typeShape = typeShapeSignal(for: summary) else {
            return nil
        }
        var signals: [Signal] = [typeShape]
        if let name = nameSignal(for: summary, vocabulary: vocabulary) {
            signals.append(name)
        }
        if let counter = antiCommutativitySignal(for: summary, vocabulary: vocabulary) {
            signals.append(counter)
        }
        if let veto = nonDeterministicVeto(for: summary) {
            signals.append(veto)
        }
        let score = Score(signals: signals)
        guard score.tier != .suppressed else {
            return nil
        }
        return Suggestion(
            templateName: "commutativity",
            evidence: [makeEvidence(summary)],
            score: score,
            generator: .m1Placeholder,
            explainability: makeExplainability(for: summary, signals: signals),
            identity: makeIdentity(for: summary)
        )
    }

    /// Canonical hash input per PRD §7.5: `template ID | canonical
    /// signature`. Reuses `IdempotenceTemplate.canonicalSignature`'s
    /// stable form (`Container.name(label1:label2:)|(T1,T2)->R`) so
    /// suggestion identities for the same function under different
    /// templates are namespaced by the leading template ID.
    private static func makeIdentity(for summary: FunctionSummary) -> SuggestionIdentity {
        SuggestionIdentity(canonicalInput: "commutativity|" + IdempotenceTemplate.canonicalSignature(of: summary))
    }

    // MARK: - Signals

    private static func typeShapeSignal(for summary: FunctionSummary) -> Signal? {
        guard summary.parameters.count == 2,
              !summary.isMutating else {
            return nil
        }
        let first = summary.parameters[0]
        let second = summary.parameters[1]
        guard !first.isInout,
              !second.isInout,
              first.typeText == second.typeText,
              let returnType = summary.returnTypeText,
              returnType == first.typeText,
              returnType != "Void",
              returnType != "()" else {
            return nil
        }
        return Signal(
            kind: .typeSymmetrySignature,
            weight: 30,
            detail: "Type-symmetry signature: (T, T) -> T (T = \(returnType))"
        )
    }

    private static func nameSignal(
        for summary: FunctionSummary,
        vocabulary: Vocabulary
    ) -> Signal? {
        if curatedVerbs.contains(summary.name) {
            return Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Curated commutativity verb match: '\(summary.name)'"
            )
        }
        if vocabulary.commutativityVerbs.contains(summary.name) {
            return Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Project-vocabulary commutativity verb match: '\(summary.name)'"
            )
        }
        return nil
    }

    private static func antiCommutativitySignal(
        for summary: FunctionSummary,
        vocabulary: Vocabulary
    ) -> Signal? {
        if curatedAntiCommutativityVerbs.contains(summary.name) {
            return Signal(
                kind: .antiCommutativityNaming,
                weight: -30,
                detail: "Curated anti-commutativity verb match: '\(summary.name)'"
            )
        }
        if vocabulary.antiCommutativityVerbs.contains(summary.name) {
            return Signal(
                kind: .antiCommutativityNaming,
                weight: -30,
                detail: "Project-vocabulary anti-commutativity verb match: '\(summary.name)'"
            )
        }
        return nil
    }

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
            "T must conform to Equatable for the emitted property to compile. "
                + "SwiftInfer M1 does not verify protocol conformance — confirm before applying.",
            "If T is a class with a custom ==, the property is over value equality as T.== defines it."
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
