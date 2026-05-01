import SwiftInferCore

/// Associativity template — `f: (T, T) -> T` where applying `f` to three
/// arguments grouped either way yields the same result:
/// `f(f(a, b), c) == f(a, f(b, c))`. Single-function template (no
/// cross-function pairing); scoring drawn from PRD v0.3 §4 + §5.2.
///
/// Necessary type pattern (PRD §5.2): identical to commutativity —
///   - exactly two parameters
///   - neither parameter is `inout`
///   - both parameter types match each other
///   - return type matches the parameter type
///   - function is not `mutating`
///   - return type is not `Void` / `()`
///
/// Naming signal: per v0.2 §5.2 ("Name signals: same as commutativity.
/// Often suggested alongside."), the curated commutativity verb list
/// (`add`, `combine`, `merge`, `union`, `intersect`) and the project's
/// `commutativityVerbs` vocab key are reused at the same +40 weight. No
/// dedicated `associativityVerbs` key in M2 per the open-decision in
/// `docs/M2 Plan.md` — keeps `vocabulary.json` schema small until a
/// non-commutative associative case (e.g. `concat`) demands a separate
/// list. Anti-commutativity verbs are intentionally NOT applied as a
/// counter-signal here: `concat`/`append`-family ops are typically
/// associative even when not commutative, so the asymmetry penalty
/// from M2.3 doesn't generalise.
///
/// Type-flow signal: reducer/builder usage (+20 per PRD §5.3). Fires
/// when the candidate function is referenced as the closure-position
/// argument of `.reduce(_, op)` or `.reduce(into: _, op)` anywhere in
/// the analyzed corpus — the corpus union is computed once by
/// `TemplateRegistry.discover(...)` and threaded in via `reducerOps`.
///
/// Veto: non-deterministic body, identical to idempotence and
/// commutativity. If the pattern doesn't hold, returns `nil`. If the
/// pattern holds but the score collapses to `.suppressed`, also
/// returns `nil`.
public enum AssociativityTemplate {

    /// Build a suggestion for `summary`, or return `nil` if the type
    /// pattern doesn't match or the score collapses to `.suppressed`.
    ///
    /// `vocabulary` consults the same `commutativityVerbs` key the
    /// commutativity template uses, by design (see type-doc).
    /// `reducerOps` is the corpus-wide set of function names referenced
    /// as the closure-position argument of any `.reduce(_, X)` call;
    /// callers that haven't computed this set (e.g. unit tests for the
    /// pure type-pattern path) can pass the empty default.
    public static func suggest(
        for summary: FunctionSummary,
        vocabulary: Vocabulary = .empty,
        reducerOps: Set<String> = []
    ) -> Suggestion? {
        guard let typeShape = typeShapeSignal(for: summary) else {
            return nil
        }
        var signals: [Signal] = [typeShape]
        if let name = nameSignal(for: summary, vocabulary: vocabulary) {
            signals.append(name)
        }
        if let reducer = reducerUsageSignal(for: summary, reducerOps: reducerOps) {
            signals.append(reducer)
        }
        if let veto = nonDeterministicVeto(for: summary) {
            signals.append(veto)
        }
        let score = Score(signals: signals)
        guard score.tier != .suppressed else {
            return nil
        }
        return Suggestion(
            templateName: "associativity",
            evidence: [makeEvidence(summary)],
            score: score,
            generator: .m1Placeholder,
            explainability: makeExplainability(for: summary, signals: signals),
            identity: makeIdentity(for: summary)
        )
    }

    /// Canonical hash input per PRD §7.5: `template ID | canonical
    /// signature`. Reuses `IdempotenceTemplate.canonicalSignature` so
    /// the associativity identity for a function is namespaced solely
    /// by the `associativity|` prefix — same function under
    /// commutativity / idempotence produces a distinct hash.
    private static func makeIdentity(for summary: FunctionSummary) -> SuggestionIdentity {
        SuggestionIdentity(canonicalInput: "associativity|" + IdempotenceTemplate.canonicalSignature(of: summary))
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
        if CommutativityTemplate.curatedVerbs.contains(summary.name) {
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

    private static func reducerUsageSignal(
        for summary: FunctionSummary,
        reducerOps: Set<String>
    ) -> Signal? {
        guard reducerOps.contains(summary.name) else {
            return nil
        }
        return Signal(
            kind: .reduceFoldUsage,
            weight: 20,
            detail: "Reduce/fold usage detected in corpus: '\(summary.name)' referenced as a reducer op"
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
            whySuggested.append(signal.formattedLine)
        }
        let caveats: [String] = [
            "T must conform to Equatable for the emitted property to compile. "
                + "SwiftInfer M1 does not verify protocol conformance — confirm before applying.",
            "If T is a class with a custom ==, the property is over value equality as T.== defines it.",
            "Floating-point operations are typically not exactly associative under IEEE 754 — "
                + "a Double-typed candidate may pass the type pattern but fail sampling under M4."
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
