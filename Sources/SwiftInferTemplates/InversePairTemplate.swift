import SwiftInferCore

/// Inverse-pair template — `f: T -> U` paired with `g: U -> T` where
/// `T` does *not* classify as `Equatable` per `EquatableResolver`
/// (M3.3). Fills the gap RoundTripTemplate (M1.4) leaves: round-trip
/// vetoes when `T` is not Equatable since its emitted property uses
/// `==`; inverse-pair surfaces the structural claim as a Possible-tier
/// informational suggestion the user can act on with a custom equality
/// witness or annotation API extension.
///
/// Necessary type pattern (PRD v0.4 §5.2 + §5.8 M8 row): the pair's
/// type shape (enforced by `FunctionPairing`) plus `T` *not*
/// classifying as `.equatable`. Equatable `T` defers to RoundTripTemplate;
/// this template only fires when the resolver returns `.notEquatable` or
/// `.unknown` for the forward param type. When no resolver is supplied
/// (test/programmatic-discovery callers that haven't threaded
/// `typeDecls` through), the template assumes "non-Equatable" so it
/// still fires — same posture as RoundTripTemplate's `vocabulary: .empty`
/// default.
///
/// Score lands in the Possible tier (20–39) per PRD v0.4 §5.8's
/// "suppressed by default" posture — type-pattern alone scores 25;
/// curated naming or project-vocabulary `inversePairs` adds 10.
/// Hidden behind `--include-possible` per the §5.8 M8 row; explicit
/// `--include-possible` exposes them. The type-flow `g(f(x))`
/// composition signal (PRD §5.3 inverse-by-usage) is *not* shipped in
/// M8.1 because `BodySignals` doesn't carry an inverse-composition
/// flag yet — `hasSelfComposition` only catches `f(f(x))`. Adding the
/// flag is a small `FunctionScanner` extension; deferred to v1.1+ per
/// the M8 plan ("the type-flow `g(f(x))` composition signal ... lands
/// once `BodySignals` surface this").
public enum InversePairTemplate {

    /// `vocabulary` is the project-extensible naming layer per PRD §4.5;
    /// the template consults `vocabulary.inversePairs` alongside the
    /// curated list shared with `RoundTripTemplate`.
    ///
    /// `equatableResolver` gates the template — `nil` defaults to "fire"
    /// so callers without corpus type-decls (tests, programmatic
    /// callers) still surface the suggestion; CLI / `discover(in:)`
    /// passes a real resolver built from the scanned `typeDecls`.
    public static func suggest(
        for pair: FunctionPair,
        vocabulary: Vocabulary = .empty,
        equatableResolver: EquatableResolver? = nil
    ) -> Suggestion? {
        // Forward param type — `T` in the `f: T -> U` pair.
        guard let domain = pair.forward.parameters.first?.typeText else {
            return nil
        }
        // Equatable T → defer to RoundTripTemplate. `.notEquatable` and
        // `.unknown` both fire — the latter because the resolver can't
        // confirm Equatable conformance for arbitrary corpus types, and
        // the surfaced caveat in the §4.5 block tells the user why.
        if let resolver = equatableResolver,
           resolver.classify(typeText: domain) == .equatable {
            return nil
        }
        var signals: [Signal] = [typeSymmetrySignal(for: pair)]
        if let name = nameSignal(for: pair, vocabulary: vocabulary) {
            signals.append(name)
        }
        if let veto = nonDeterministicVeto(for: pair) {
            signals.append(veto)
        }
        let score = Score(signals: signals)
        guard score.tier != .suppressed else {
            return nil
        }
        return Suggestion(
            templateName: "inverse-pair",
            evidence: [makeEvidence(pair.forward), makeEvidence(pair.reverse)],
            score: score,
            generator: .m1Placeholder,
            explainability: makeExplainability(for: pair, signals: signals),
            identity: makeIdentity(for: pair)
        )
    }

    /// Canonical hash input per PRD §7.5: `template ID | canonical
    /// signature A | canonical signature B`, where A and B are sorted
    /// lexicographically so the hash is orientation-agnostic. Mirrors
    /// `RoundTripTemplate.makeIdentity` so the two templates produce
    /// distinct identity hashes for the same pair (different template
    /// prefix), avoiding collision in the decisions / baseline files.
    private static func makeIdentity(for pair: FunctionPair) -> SuggestionIdentity {
        let forwardSig = IdempotenceTemplate.canonicalSignature(of: pair.forward)
        let reverseSig = IdempotenceTemplate.canonicalSignature(of: pair.reverse)
        let sorted = [forwardSig, reverseSig].sorted()
        return SuggestionIdentity(canonicalInput: "inverse-pair|" + sorted.joined(separator: "|"))
    }

    // MARK: - Signals

    private static func typeSymmetrySignal(for pair: FunctionPair) -> Signal {
        let domain = pair.forward.parameters.first?.typeText ?? "?"
        let codomain = pair.forward.returnTypeText ?? "?"
        return Signal(
            kind: .typeSymmetrySignature,
            weight: 25,
            detail: "Type-symmetry signature: \(domain) -> \(codomain) ↔ \(codomain) -> \(domain) (non-Equatable T)"
        )
    }

    private static func nameSignal(
        for pair: FunctionPair,
        vocabulary: Vocabulary
    ) -> Signal? {
        let forwardName = pair.forward.name
        let reverseName = pair.reverse.name
        // Reuses `RoundTripTemplate.curatedInversePairs` — the curated
        // list applies regardless of whether T is Equatable; the
        // semantics of the inversion don't change with the codomain
        // type's value-equality story.
        if let curated = RoundTripTemplate.curatedInversePairs.first(where: { tuple in
            matches(forwardName: forwardName, reverseName: reverseName, lhs: tuple.0, rhs: tuple.1)
        }) {
            return Signal(
                kind: .exactNameMatch,
                weight: 10,
                detail: "Curated inverse name pair: \(curated.0)/\(curated.1)"
            )
        }
        if let projectPair = vocabulary.inversePairs.first(where: { entry in
            matches(forwardName: forwardName, reverseName: reverseName, lhs: entry.forward, rhs: entry.reverse)
        }) {
            return Signal(
                kind: .exactNameMatch,
                weight: 10,
                detail: "Project-vocabulary inverse pair match: "
                    + "\(projectPair.forward)/\(projectPair.reverse)"
            )
        }
        return nil
    }

    private static func matches(
        forwardName: String,
        reverseName: String,
        lhs: String,
        rhs: String
    ) -> Bool {
        let direct = forwardName == lhs && reverseName == rhs
        let swapped = forwardName == rhs && reverseName == lhs
        return direct || swapped
    }

    private static func nonDeterministicVeto(for pair: FunctionPair) -> Signal? {
        let forwardCalls = pair.forward.bodySignals.nonDeterministicAPIsDetected
        let reverseCalls = pair.reverse.bodySignals.nonDeterministicAPIsDetected
        let both = Array(Set(forwardCalls).union(reverseCalls)).sorted()
        guard !both.isEmpty else {
            return nil
        }
        let side = describeAffectedSide(pair: pair)
        return Signal(
            kind: .nonDeterministicBody,
            weight: Signal.vetoWeight,
            detail: "Non-deterministic API in \(side): \(both.joined(separator: ", "))"
        )
    }

    private static func describeAffectedSide(pair: FunctionPair) -> String {
        let forwardHas = pair.forward.bodySignals.hasNonDeterministicCall
        let reverseHas = pair.reverse.bodySignals.hasNonDeterministicCall
        switch (forwardHas, reverseHas) {
        case (true, true): return "both bodies"
        case (true, false): return "\(pair.forward.name) body"
        case (false, true): return "\(pair.reverse.name) body"
        case (false, false): return "neither body"
        }
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
        for pair: FunctionPair,
        signals: [Signal]
    ) -> ExplainabilityBlock {
        var whySuggested: [String] = []
        let forwardEvidence = makeEvidence(pair.forward)
        let reverseEvidence = makeEvidence(pair.reverse)
        whySuggested.append(
            "\(forwardEvidence.displayName) \(forwardEvidence.signature)"
                + " — \(forwardEvidence.location.file):\(forwardEvidence.location.line)"
        )
        whySuggested.append(
            "\(reverseEvidence.displayName) \(reverseEvidence.signature)"
                + " — \(reverseEvidence.location.file):\(reverseEvidence.location.line)"
        )
        for signal in signals {
            whySuggested.append(signal.formattedLine)
        }
        let caveats: [String] = [
            "Non-Equatable T means SwiftInfer cannot sample-verify the round-trip — "
                + "the suggestion is name-and-type-pattern only.",
            "TestLifter corroboration not yet wired (gated on TestLifter M1).",
            "Possible-tier by default — escalation requires a custom equality witness "
                + "or annotation API extension.",
            "If T conforms to Equatable, RoundTripTemplate (M1.4) handles this case "
                + "with stronger evidence — inverse-pair only fires when "
                + "EquatableResolver returns .notEquatable or .unknown for T."
        ]
        return ExplainabilityBlock(whySuggested: whySuggested, whyMightBeWrong: caveats)
    }

    // MARK: - Display helpers (mirrors RoundTripTemplate)

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
