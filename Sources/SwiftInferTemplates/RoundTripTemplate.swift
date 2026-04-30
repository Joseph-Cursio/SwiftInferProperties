import SwiftInferCore

/// Round-trip template — `f: T -> U` paired with `g: U -> T` where
/// `g(f(t)) == t`. Cross-function: consumes `FunctionPair`s produced by
/// `FunctionPairing` rather than individual summaries.
///
/// Necessary type pattern (PRD §5.2): the pair's type shape (enforced by
/// `FunctionPairing`'s type filter) plus `T: Equatable`. M1.4 cannot
/// verify protocol conformance — see the always-rendered Equatable
/// caveat in the §4.5 explainability block.
///
/// Counter-signals: non-Equatable `T` (-∞ veto, structurally untestable —
/// can only be applied at M3+ once semantic resolution lands); type-flow
/// detection of non-deterministic API calls in *either* body is a -∞
/// veto (Appendix B.3 + B.4).
public enum RoundTripTemplate {

    /// Curated inverse-name pairs per PRD v0.3 §5.2. Project-vocabulary
    /// extension (§4.5's `inversePairs` from `vocabulary.json`) lands at
    /// M2; M1.4 ships the curated list, exact-match in either order.
    public static let curatedInversePairs: [(String, String)] = [
        ("encode", "decode"),
        ("serialize", "deserialize"),
        ("compress", "decompress"),
        ("encrypt", "decrypt"),
        ("parse", "format"),
        ("push", "pop"),
        ("insert", "remove"),
        ("open", "close"),
        ("marshal", "unmarshal"),
        ("pack", "unpack"),
        ("lock", "unlock")
    ]

    /// `vocabulary` is the project-extensible naming layer per PRD §4.5;
    /// the template consults `vocabulary.inversePairs` alongside the
    /// curated list. Defaults to `.empty` so M1 call sites compile
    /// unchanged.
    public static func suggest(
        for pair: FunctionPair,
        vocabulary: Vocabulary = .empty
    ) -> Suggestion? {
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
            templateName: "round-trip",
            evidence: [makeEvidence(pair.forward), makeEvidence(pair.reverse)],
            score: score,
            generator: .m1Placeholder,
            explainability: makeExplainability(for: pair, signals: signals),
            identity: makeIdentity(for: pair)
        )
    }

    /// Canonical hash input per PRD §7.5: `template ID | canonical
    /// signature A | canonical signature B`, where A and B are sorted
    /// lexicographically so the hash is orientation-agnostic. A pair
    /// produces the same identity regardless of which half
    /// `FunctionPairing` chose as `forward`.
    private static func makeIdentity(for pair: FunctionPair) -> SuggestionIdentity {
        let forwardSig = IdempotenceTemplate.canonicalSignature(of: pair.forward)
        let reverseSig = IdempotenceTemplate.canonicalSignature(of: pair.reverse)
        let sorted = [forwardSig, reverseSig].sorted()
        return SuggestionIdentity(canonicalInput: "round-trip|" + sorted.joined(separator: "|"))
    }

    // MARK: - Signals

    private static func typeSymmetrySignal(for pair: FunctionPair) -> Signal {
        let domain = pair.forward.parameters.first?.typeText ?? "?"
        let codomain = pair.forward.returnTypeText ?? "?"
        return Signal(
            kind: .typeSymmetrySignature,
            weight: 30,
            detail: "Type-symmetry signature: \(domain) -> \(codomain) ↔ \(codomain) -> \(domain)"
        )
    }

    private static func nameSignal(
        for pair: FunctionPair,
        vocabulary: Vocabulary
    ) -> Signal? {
        let forwardName = pair.forward.name
        let reverseName = pair.reverse.name
        // Curated takes precedence over project vocabulary so a pair
        // already in the curated list never double-fires when the project
        // happens to repeat it. Both contribute the same +40 weight per
        // PRD §4.5; only the rendered detail line distinguishes them.
        if let curated = curatedInversePairs.first(where: { tuple in
            matches(forwardName: forwardName, reverseName: reverseName, lhs: tuple.0, rhs: tuple.1)
        }) {
            return Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Curated inverse name pair: \(curated.0)/\(curated.1)"
            )
        }
        if let projectPair = vocabulary.inversePairs.first(where: { entry in
            matches(forwardName: forwardName, reverseName: reverseName, lhs: entry.forward, rhs: entry.reverse)
        }) {
            return Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Project-vocabulary inverse name pair: "
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
            whySuggested.append(formatSignalLine(signal))
        }
        let caveats: [String] = [
            "Throws on either side narrows the property's domain to the success set "
                + "of the inner function; a generator that produces values outside that "
                + "set will surface false-positive failures (Appendix B.4).",
            "T must conform to Equatable for the emitted property to compile. "
                + "SwiftInfer M1 does not verify protocol conformance — confirm before applying."
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
