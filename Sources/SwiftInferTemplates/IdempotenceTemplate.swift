import SwiftInferCore

/// Idempotence template — `f: T -> T` where applying `f` twice equals
/// applying it once. The simplest M1 template: single-function, no
/// pairing, scoring drawn from PRD v0.3 §4 + §5.2.
///
/// Necessary type pattern (PRD §5.2):
///   - exactly one parameter
///   - parameter is not `inout`
///   - return type text equals the parameter type text
///   - function is not `mutating`
///
/// If the pattern doesn't hold, the template returns `nil` — the suggestion
/// flow never emits anything for that function. If the pattern holds and a
/// veto signal fires (non-deterministic body per §4.1's -∞ row), the
/// resulting score collapses to `.suppressed` and the template still
/// returns `nil`. Suppressed suggestions are never rendered.
public enum IdempotenceTemplate {

    /// Curated idempotence-verb list per PRD v0.3 §5.2. Project-vocabulary
    /// extension (§4.5's `idempotenceVerbs` from `vocabulary.json`) lands
    /// at M2; for M1.3 the list is the curated set, exact-match only.
    public static let curatedVerbs: Set<String> = [
        "normalize",
        "canonicalize",
        "trim",
        "flatten",
        "sort",
        "deduplicate",
        "sanitize",
        "format"
    ]

    /// Build a suggestion for `summary`, or return `nil` if the type
    /// pattern doesn't match or the score collapses to `.suppressed`.
    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        guard let typeSymmetry = typeSymmetrySignal(for: summary) else {
            return nil
        }
        var signals: [Signal] = [typeSymmetry]
        if let name = nameSignal(for: summary) {
            signals.append(name)
        }
        if let composition = selfCompositionSignal(for: summary) {
            signals.append(composition)
        }
        if let veto = nonDeterministicVeto(for: summary) {
            signals.append(veto)
        }
        let score = Score(signals: signals)
        guard score.tier != .suppressed else {
            return nil
        }
        return Suggestion(
            templateName: "idempotence",
            evidence: [makeEvidence(summary)],
            score: score,
            generator: .m1Placeholder,
            explainability: makeExplainability(for: summary, signals: signals),
            identity: makeIdentity(for: summary)
        )
    }

    /// Canonical hash input per PRD §7.5: `template ID | canonical
    /// signature`. Source location is intentionally excluded — moving a
    /// function within a file or across files must not change its
    /// identity. Containing-type name *is* included; two unrelated types
    /// can have a method named `normalize(_:)` and they produce distinct
    /// suggestions.
    private static func makeIdentity(for summary: FunctionSummary) -> SuggestionIdentity {
        SuggestionIdentity(canonicalInput: "idempotence|" + canonicalSignature(of: summary))
    }

    /// Stable string form of a function signature: `Container.name(label1:label2:)|(T1,T2)->R`.
    /// Order-stable by parameter declaration order; spaces stripped so the
    /// hash is robust against trivial source reformatting.
    static func canonicalSignature(of summary: FunctionSummary) -> String {
        let typePrefix = summary.containingTypeName.map { "\($0)." } ?? ""
        let labels = summary.parameters.map { ($0.label ?? "_") + ":" }.joined()
        let paramTypes = summary.parameters.map(\.typeText).joined(separator: ",")
        let returnType = summary.returnTypeText ?? "Void"
        return "\(typePrefix)\(summary.name)(\(labels))|(\(paramTypes))->\(returnType)"
    }

    // MARK: - Signals

    private static func typeSymmetrySignal(for summary: FunctionSummary) -> Signal? {
        guard summary.parameters.count == 1,
              let param = summary.parameters.first,
              !param.isInout,
              !summary.isMutating,
              let returnType = summary.returnTypeText,
              returnType == param.typeText,
              returnType != "Void",
              returnType != "()" else {
            return nil
        }
        return Signal(
            kind: .typeSymmetrySignature,
            weight: 30,
            detail: "Type-symmetry signature: T -> T (T = \(returnType))"
        )
    }

    private static func nameSignal(for summary: FunctionSummary) -> Signal? {
        guard curatedVerbs.contains(summary.name) else {
            return nil
        }
        return Signal(
            kind: .exactNameMatch,
            weight: 40,
            detail: "Curated idempotence verb match: '\(summary.name)'"
        )
    }

    private static func selfCompositionSignal(for summary: FunctionSummary) -> Signal? {
        guard summary.bodySignals.hasSelfComposition else {
            return nil
        }
        return Signal(
            kind: .selfComposition,
            weight: 20,
            detail: "Self-composition detected in body: \(summary.name)(\(summary.name)(x))"
        )
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
            whySuggested.append(formatSignalLine(signal))
        }
        let caveats: [String] = [
            "T must conform to Equatable for the emitted property to compile. "
                + "SwiftInfer M1 does not verify protocol conformance — confirm before applying.",
            "If T is a class with a custom ==, the property is over value equality as T.== defines it."
        ]
        return ExplainabilityBlock(whySuggested: whySuggested, whyMightBeWrong: caveats)
    }

    private static func formatSignalLine(_ signal: Signal) -> String {
        if signal.isVeto {
            return "\(signal.detail) (veto)"
        }
        let sign = signal.weight >= 0 ? "+" : ""
        return "\(signal.detail) (\(sign)\(signal.weight))"
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
