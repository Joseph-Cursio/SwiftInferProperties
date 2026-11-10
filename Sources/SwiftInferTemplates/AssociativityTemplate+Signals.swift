import SwiftInferCore

// V1.43 cleanup — signals/vetoes/builders live here so the primary
// enum body stays under SwiftLint's type_body_length cap.
extension AssociativityTemplate {

    // MARK: - Signals

    static func nameSignal(
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

    static func reducerUsageSignal(
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

    /// Concatenation-family names that suggest a genuinely *associative*
    /// operation even though it is not commutative — list/string `++`-style
    /// joins. These corroborate associativity (they keep the shape-only counter
    /// below from firing), but deliberately do NOT earn the `+40` curated-verb
    /// bump, so a `concat` still surfaces at the Possible tier rather than being
    /// promoted to a shown-by-default Strong. Distinct from the commutativity
    /// template's anti-commutativity list, which *suppresses* these — a concat
    /// is associative but not commutative.
    static let curatedAssociativeVerbs: Set<String> = [
        "concat", "concatenate", "concatenated", "concatenating",
        "append", "appending", "prepend", "prepending", "joined",
    ]

    /// Operator spellings that name a canonically associative op. `+` and `*`
    /// are associative (and are what the protocol-coverage map already treats as
    /// additive / multiplicative); `-` and `/` are not, so they stay gated. These
    /// corroborate the shape without the `+40` curated bump, so `+` keeps its
    /// existing Possible-tier associativity rather than being promoted.
    static let knownAlgebraicOperators: Set<String> = ["+", "*"]

    /// Textbook associative-AND-commutative word ops beyond the curated verbs:
    /// semilattice (`join`, `meet`), order (`min`, `max`), number-theory (`gcd`,
    /// `lcm`). Corroborate BOTH templates without the `+40` bump (kept at
    /// Possible). Unlike `leftBiased` / `weighted`, whose shape entails nothing.
    static let commutativeAssociativeVerbs: Set<String> = [
        "join", "meet", "min", "max", "gcd", "lcm"
    ]

    /// B24 — counter-signal that suppresses a shape-only associativity candidate.
    /// Fires when the `(T, T) -> T` shape matched but nothing corroborates that
    /// the operation is a genuine monoid: no curated / vocabulary name, no
    /// concatenation-family name, and it is never used as a reduce/fold op in the
    /// corpus. The bare shape matches a correct `backoffDelay` / `weighted` /
    /// `scaleQuantity`, none of which is associative, so a shape-only proposal
    /// spends the reader's trust for nothing. `-20` drops Score 30 → 10, below the
    /// Possible floor; a real corroboration keeps this from firing.
    static func unsupportedShapeCounterSignal(
        for summary: FunctionSummary,
        vocabulary: Vocabulary,
        reducerOps: Set<String>
    ) -> Signal? {
        let hasName = nameSignal(for: summary, vocabulary: vocabulary) != nil
        let hasAssociativeName = curatedAssociativeVerbs.contains(summary.name)
        let hasAlgebraicVerb = commutativeAssociativeVerbs.contains(summary.name)
        let hasOperator = knownAlgebraicOperators.contains(summary.name)
        let hasReducer = reducerOps.contains(summary.name)
        guard !hasName, !hasAssociativeName, !hasAlgebraicVerb, !hasOperator, !hasReducer else {
            return nil
        }
        return Signal(
            kind: .unsupportedAlgebraicShape,
            weight: -20,
            detail: "'\(summary.name)' matched only the (T, T) -> T shape — no monoid/concat "
                + "name and no reduce-fold usage; associativity is not entailed by the shape alone"
        )
    }

    /// V1.5.2 — fires when the candidate type's existing protocol
    /// conformances cover the associativity property the template
    /// would emit, mapped op-class-aware: `+` → additive, `*` →
    /// multiplicative, `union`/`formUnion` → set-union. Mirrors
    /// CommutativityTemplate's helper but targets the `*Associative`
    /// properties.
    static func assumedKitCoverage(
        for summary: FunctionSummary,
        inheritedTypesByName: [String: Set<String>]
    ) -> Signal? {
        let candidates = associativityCoverageCandidates(forOp: summary.name)
        guard !candidates.isEmpty else { return nil }
        return ProtocolCoverageMap.assumedCoverageSignal(
            forTypeText: summary.parameters.first?.typeText,
            inheritedTypesByName: inheritedTypesByName,
            candidateProperties: candidates
        )
    }

    /// V1.5.2 — op-class → KnownProperty candidate set for the
    /// associativity veto. Same op classification as commutativity;
    /// kept as its own table for clarity (and so a future per-template
    /// op-class change doesn't accidentally split commutativity from
    /// associativity).
    static func associativityCoverageCandidates(forOp opName: String) -> [KnownProperty] {
        switch opName {
        case "+":
            return [.additiveAssociative]

        case "*":
            return [.multiplicativeAssociative]

        // No case for the set verbs, and that is the point. Until 2026-08-02
        // `"union"`/`"formUnion"` returned `.setUnionAssociative` and the veto
        // suppressed the suggestion, citing `checkSetAlgebraPropertyLaws` — which
        // ships fifteen laws and no associativity law for any set operand. Set
        // associativity is a true, refutable law that nothing else runs, so it is
        // `discover`'s to propose. See `docs/measurements/protocol-coverage-law-drift.md` §3;
        // re-adding a candidate here requires adding the law to the kit first.
        default:
            return []
        }
    }

    // MARK: - Suggestion construction

    static func makeExplainability(
        for summary: FunctionSummary,
        signals: [Signal]
    ) -> ExplainabilityBlock {
        var whySuggested: [String] = []
        let evidence = summary.inferenceEvidence
        whySuggested.append(
            "\(evidence.displayName) \(evidence.signature) — \(evidence.location)"
        )
        for signal in signals {
            whySuggested.append(signal.formattedLine)
        }
        var caveats: [String] = [
            "T must conform to Equatable for the emitted property to compile. "
                + "This tool does not verify protocol conformance — confirm before applying.",
            "If T is a class with a custom ==, the property is over value equality as T.== defines it.",
        ]
        if let fpCaveat = floatingPointAdvisory(for: summary) {
            caveats.append(fpCaveat)
        } else {
            caveats.append(
                "Floating-point operations are typically not exactly associative under IEEE 754 — "
                    + "a Double-typed candidate may pass the type pattern but fail sampling under M4."
            )
        }
        return ExplainabilityBlock(whySuggested: whySuggested, whyMightBeWrong: caveats)
    }
}
