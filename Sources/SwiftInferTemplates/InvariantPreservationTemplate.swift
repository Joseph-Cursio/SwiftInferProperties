import SwiftInferCore

/// Invariant-preservation template — `inv(f(x))` whenever `inv(x)`. PRD
/// v0.4 §5.2 + M7.2 plan row.
///
/// **Annotation-only.** Unlike every other template that fires on
/// signature shape and naming, this one fires ONLY when the user has
/// tagged the function with
/// `@CheckProperty(.preservesInvariant(\.somePredicate))`. Per the §5.2
/// caveat, invariant preservation is structurally too easy to misinfer
/// from signature shape alone; an explicit user opt-in is the prerequisite.
/// Functions whose name strongly suggests preservation (`mutate`,
/// `apply`, `updateInPlace`, etc.) but lack the annotation produce no
/// suggestion.
///
/// The annotation's keypath argument is captured opaquely as source text
/// (M7 plan open decision #5(a)). The template carries the keypath
/// through `Evidence.detail` so the M7.3 `LiftedTestEmitter` can emit a
/// property test of the form
/// `if input[keyPath: kp] then output[keyPath: kp]`. Keypath validity
/// against the parameter type is the user's responsibility — a malformed
/// keypath surfaces as a compile error in the user's test target, not at
/// scan time. M7 plan §"Out of scope" defers macro-side keypath
/// validation to v1.1+ once the SemanticIndex (PRD §20.1) ships.
///
/// **Tier policy.** The annotation alone scores +80, landing in the
/// `.strong` tier (>= 75). A non-deterministic body call vetoes the
/// suggestion (same posture as `IdempotenceTemplate` — repeated calls
/// can't preserve any invariant if the function returns a different
/// value each time). Other signals are not added because the §5.2
/// posture is "the annotation is the signal"; broadening it would
/// re-open the misinference risk the annotation requirement was meant
/// to close.
public enum InvariantPreservationTemplate {

    /// Build a suggestion for `summary`, or return `nil` if the function
    /// carries no `@CheckProperty(.preservesInvariant(\.foo))` annotation
    /// or if the score collapses to `.suppressed` via a veto.
    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        guard let keyPath = summary.invariantKeypath else {
            return nil
        }
        var signals: [Signal] = [annotationSignal(keyPath: keyPath)]
        if let veto = nonDeterministicVeto(for: summary) {
            signals.append(veto)
        }
        let score = Score(signals: signals)
        guard score.tier != .suppressed else {
            return nil
        }
        return Suggestion(
            templateName: "invariant-preservation",
            evidence: [makeEvidence(summary, keyPath: keyPath)],
            score: score,
            generator: .m1Placeholder,
            explainability: makeExplainability(for: summary, keyPath: keyPath, signals: signals),
            identity: makeIdentity(for: summary, keyPath: keyPath)
        )
    }

    /// Canonical hash input per PRD §7.5: `template ID | canonical
    /// signature | keypath`. Keypath is part of the identity because the
    /// same function with two different invariant annotations is two
    /// distinct property claims (e.g., `\.isValid` vs `\.isNonNegative`)
    /// — accepting one and rejecting the other must be representable in
    /// the M6.1 decisions persistence.
    private static func makeIdentity(for summary: FunctionSummary, keyPath: String) -> SuggestionIdentity {
        let canonical = "invariant-preservation|"
            + IdempotenceTemplate.canonicalSignature(of: summary)
            + "|" + keyPath
        return SuggestionIdentity(canonicalInput: canonical)
    }

    // MARK: - Signals

    private static func annotationSignal(keyPath: String) -> Signal {
        Signal(
            kind: .discoverableAnnotation,
            weight: 80,
            detail: "@CheckProperty(.preservesInvariant(\(keyPath))) annotation present"
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

    private static func makeEvidence(_ summary: FunctionSummary, keyPath: String) -> Evidence {
        Evidence(
            displayName: displayName(for: summary),
            signature: signature(for: summary, keyPath: keyPath),
            location: summary.location
        )
    }

    private static func makeExplainability(
        for summary: FunctionSummary,
        keyPath: String,
        signals: [Signal]
    ) -> ExplainabilityBlock {
        var whySuggested: [String] = []
        let evidence = makeEvidence(summary, keyPath: keyPath)
        whySuggested.append(
            "\(evidence.displayName) \(evidence.signature) — \(evidence.location.file):\(evidence.location.line)"
        )
        for signal in signals {
            whySuggested.append(signal.formattedLine)
        }
        let caveats: [String] = [
            "Keypath \(keyPath) is opaque text — user-side compile error if it doesn't "
                + "resolve against the parameter type. M7.2 does not validate keypaths at "
                + "scan time per M7 plan open decision #5(a); SemanticIndex (PRD §20.1) "
                + "lifts that to scan-time in v1.1+.",
            "Doesn't fire without explicit @CheckProperty(.preservesInvariant(_:)) "
                + "annotation per the §5.2 caveat — the M5.2 macro is the opt-in path.",
            "if invariant(x) then invariant(f(x)) is a *one-way* implication; the test "
                + "does not verify that f rejects invalid inputs."
        ]
        return ExplainabilityBlock(whySuggested: whySuggested, whyMightBeWrong: caveats)
    }

    // MARK: - Display helpers

    private static func displayName(for summary: FunctionSummary) -> String {
        let labels = summary.parameters.map { ($0.label ?? "_") + ":" }.joined()
        return "\(summary.name)(\(labels))"
    }

    private static func signature(for summary: FunctionSummary, keyPath: String) -> String {
        let paramTypes = summary.parameters.map(\.typeText).joined(separator: ", ")
        var sig = "(\(paramTypes))"
        if summary.isAsync {
            sig += " async"
        }
        if summary.isThrows {
            sig += " throws"
        }
        sig += " -> \(summary.returnTypeText ?? "Void")"
        sig += " preserving \(keyPath)"
        return sig
    }
}
