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

    /// V1.38.B — migrated to the Constraint Engine (PRD §20.2). The
    /// template's keypath dependency is derived from
    /// `summary.invariantKeypath` inside each constraint closure
    /// rather than threaded through `suggest(...)`. No runtime inputs
    /// (simplest of all migrated templates). Behavior preserved bit-
    /// for-bit.
    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    /// V1.38.B — Constraint factory. No runtime inputs.
    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "invariant-preservation",
            appliesTo: { summary in
                summary.invariantKeypath != nil
            },
            signals: { summary in
                Self.accumulatedSignals(for: summary)
            },
            evidence: { summary in
                guard let keyPath = summary.invariantKeypath else { return [] }
                return [Self.makeEvidence(summary, keyPath: keyPath)]
            },
            identity: { summary in
                guard let keyPath = summary.invariantKeypath else {
                    // Defensive — gate already required non-nil keypath.
                    return SuggestionIdentity(canonicalInput: "invariant-preservation|<missing>")
                }
                return Self.makeIdentity(for: summary, keyPath: keyPath)
            },
            carrier: { $0.containingTypeName },
            caveats: { summary in
                guard let keyPath = summary.invariantKeypath else { return [] }
                return Self.makeCaveats(keyPath: keyPath)
            }
        )
    }

    /// V1.38.B — preserves the pre-migration signal-accumulation order.
    static func accumulatedSignals(for summary: FunctionSummary) -> [Signal] {
        guard let keyPath = summary.invariantKeypath else {
            return []
        }
        var signals: [Signal] = [annotationSignal(keyPath: keyPath)]
        if let veto = nonDeterministicVeto(for: summary) {
            signals.append(veto)
        }
        return signals
    }

    /// V1.38.B — caveat list (3 constant entries; depends on keyPath
    /// for the first caveat's display text).
    static func makeCaveats(keyPath: String) -> [String] {
        [
            "Keypath \(keyPath) is opaque text — user-side compile error if it doesn't "
                + "resolve against the parameter type. M7.2 does not validate keypaths at "
                + "scan time per M7 plan open decision #5(a); SemanticIndex (PRD §20.1) "
                + "lifts that to scan-time in v1.1+.",
            "Doesn't fire without explicit @CheckProperty(.preservesInvariant(_:)) "
                + "annotation per the §5.2 caveat — the M5.2 macro is the opt-in path.",
            "if invariant(x) then invariant(f(x)) is a *one-way* implication; the test "
                + "does not verify that f rejects invalid inputs."
        ]
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
            displayName: summary.inferenceDisplayName,
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
