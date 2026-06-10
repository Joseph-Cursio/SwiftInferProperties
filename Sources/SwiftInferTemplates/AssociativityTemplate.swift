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
    ///
    /// V1.5.2 — `inheritedTypesByName` feeds the protocol-coverage
    /// veto. Mirrors `CommutativityTemplate`'s op-class-aware shape,
    /// targeting the `*Associative` properties: `+` →
    /// `additiveAssociative` (kit `checkAdditiveArithmeticPropertyLaws`);
    /// `*` → `multiplicativeAssociative` (kit
    /// `checkNumericPropertyLaws`); `union` / `formUnion` →
    /// `setUnionAssociative` (kit `checkSetAlgebraPropertyLaws`).
    /// User-named ops fall through unsuppressed.
    /// V1.38.A — migrated to the Constraint Engine (PRD §20.2). The
    /// template now expresses itself as a `Constraint<FunctionSummary>`
    /// via `makeConstraint(vocabulary:reducerOps:inheritedTypesByName:)`,
    /// and `suggest(for:...)` is a thin wrapper that orchestrates the
    /// constraint through `ConstraintRunner.suggest`. Behavior preserved
    /// bit-for-bit (verified by the existing AssociativityTemplate test
    /// suite + V1.38.D equivalence tests).
    public static func suggest(
        for summary: FunctionSummary,
        vocabulary: Vocabulary = .empty,
        reducerOps: Set<String> = [],
        inheritedTypesByName: [String: Set<String>] = [:]
    ) -> Suggestion? {
        ConstraintRunner.suggest(
            constraint: makeConstraint(
                vocabulary: vocabulary,
                reducerOps: reducerOps,
                inheritedTypesByName: inheritedTypesByName
            ),
            subject: summary
        )
    }

    /// V1.38.A — Constraint factory. Captures runtime inputs into
    /// @Sendable closures.
    public static func makeConstraint(
        vocabulary: Vocabulary,
        reducerOps: Set<String>,
        inheritedTypesByName: [String: Set<String>]
    ) -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "associativity",
            appliesTo: { summary in
                summary.binaryOperatorTypeSymmetrySignal != nil
            },
            signals: { summary in
                Self.accumulatedSignals(
                    for: summary,
                    vocabulary: vocabulary,
                    reducerOps: reducerOps,
                    inheritedTypesByName: inheritedTypesByName
                )
            },
            evidence: { summary in
                [summary.inferenceEvidence]
            },
            identity: Self.makeIdentity(for:),
            carrier: { $0.containingTypeName },
            caveats: { summary in
                Self.makeCaveats(for: summary)
            }
        )
    }

    /// V1.38.A — preserves the pre-migration signal-accumulation order.
    static func accumulatedSignals(
        for summary: FunctionSummary,
        vocabulary: Vocabulary,
        reducerOps: Set<String>,
        inheritedTypesByName: [String: Set<String>]
    ) -> [Signal] {
        guard let typeShape = summary.binaryOperatorTypeSymmetrySignal else {
            return []
        }
        var signals: [Signal] = [typeShape]
        if let name = nameSignal(for: summary, vocabulary: vocabulary) {
            signals.append(name)
        }
        if let reducer = reducerUsageSignal(for: summary, reducerOps: reducerOps) {
            signals.append(reducer)
        }
        if let fpCounter = floatingPointStorageCounterSignal(for: summary) {
            signals.append(fpCounter)
        }
        if let veto = summary.nonDeterministicVetoSignal {
            signals.append(veto)
        }
        if let coverageVeto = protocolCoverageVeto(
            for: summary,
            inheritedTypesByName: inheritedTypesByName
        ) {
            signals.append(coverageVeto)
        }
        return signals
    }

    /// V1.38.A — caveat list for the Constraint's `caveats` closure.
    /// Always 3 entries: base 2 + (FP advisory OR fallback FP warning).
    static func makeCaveats(for summary: FunctionSummary) -> [String] {
        var caveats: [String] = [
            "T must conform to Equatable for the emitted property to compile. "
                + "SwiftInfer M1 does not verify protocol conformance — confirm before applying.",
            "If T is a class with a custom ==, the property is over value equality as T.== defines it."
        ]
        if let fpCaveat = floatingPointAdvisory(for: summary) {
            caveats.append(fpCaveat)
        } else {
            caveats.append(
                "Floating-point operations are typically not exactly associative under IEEE 754 — "
                    + "a Double-typed candidate may pass the type pattern but fail sampling under M4."
            )
        }
        return caveats
    }

    /// Canonical hash input per PRD §7.5: `template ID | canonical
    /// signature`. Reuses `IdempotenceTemplate.canonicalSignature` so
    /// the associativity identity for a function is namespaced solely
    /// by the `associativity|` prefix — same function under
    /// commutativity / idempotence produces a distinct hash.
    private static func makeIdentity(for summary: FunctionSummary) -> SuggestionIdentity {
        SuggestionIdentity(canonicalInput: "associativity|" + IdempotenceTemplate.canonicalSignature(of: summary))
    }
}

// V1.43 cleanup — signals/vetoes/builders live here so the primary
// enum body stays under SwiftLint's type_body_length cap.
extension AssociativityTemplate {

    // MARK: - Signals

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

    /// V1.4.3 — fires when the candidate's parameter type is a
    /// curated IEEE 754 floating-point-storage name (Float / Double /
    /// Float16-80 / CGFloat / Complex / Decimal). Drops Score 30 → 20
    /// (Possible-tier floor) so the suggestion stays surfaced under
    /// `--include-possible` for the explainability kit-pointer to be
    /// visible. Calibration cycle 1 tuning patch.
    private static func floatingPointStorageCounterSignal(
        for summary: FunctionSummary
    ) -> Signal? {
        guard let first = summary.parameters.first,
              FloatingPointStorageNames.contains(first.typeText) else {
            return nil
        }
        let stripped = FloatingPointStorageNames.strippingGenericParameters(first.typeText)
        return Signal(
            kind: .floatingPointStorage,
            weight: -10,
            detail: "Floating-point storage: T = \(stripped) — exact-equality "
                + "associativity is not bit-exact under IEEE 754 sampling"
        )
    }

    /// V1.5.2 — fires when the candidate type's existing protocol
    /// conformances cover the associativity property the template
    /// would emit, mapped op-class-aware: `+` → additive, `*` →
    /// multiplicative, `union`/`formUnion` → set-union. Mirrors
    /// CommutativityTemplate's helper but targets the `*Associative`
    /// properties.
    private static func protocolCoverageVeto(
        for summary: FunctionSummary,
        inheritedTypesByName: [String: Set<String>]
    ) -> Signal? {
        let candidates = associativityCoverageCandidates(forOp: summary.name)
        guard !candidates.isEmpty else { return nil }
        return ProtocolCoverageMap.coverageVetoSignal(
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

        case "union", "formUnion":
            return [.setUnionAssociative]

        default:
            return []
        }
    }

    // MARK: - Suggestion construction

    private static func makeExplainability(
        for summary: FunctionSummary,
        signals: [Signal]
    ) -> ExplainabilityBlock {
        var whySuggested: [String] = []
        let evidence = summary.inferenceEvidence
        whySuggested.append(
            "\(evidence.displayName) \(evidence.signature) — \(evidence.location.file):\(evidence.location.line)"
        )
        for signal in signals {
            whySuggested.append(signal.formattedLine)
        }
        var caveats: [String] = [
            "T must conform to Equatable for the emitted property to compile. "
                + "SwiftInfer M1 does not verify protocol conformance — confirm before applying.",
            "If T is a class with a custom ==, the property is over value equality as T.== defines it."
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

    /// V1.4.3 — produces a type-aware floating-point caveat when the
    /// candidate's parameter type is FP-storage, replacing the static
    /// "may fail sampling" warning with a more specific kit-pointer or
    /// cycle-2 deferral note. Returns `nil` when T isn't FP-storage —
    /// the caller falls back to the static M1-era warning.
    private static func floatingPointAdvisory(for summary: FunctionSummary) -> String? {
        guard let first = summary.parameters.first,
              FloatingPointStorageNames.contains(first.typeText) else {
            return nil
        }
        let stripped = FloatingPointStorageNames.strippingGenericParameters(first.typeText)
        if FloatingPointStorageNames.isKitSupported(first.typeText) {
            return "T = \(stripped) conforms to FloatingPoint. Associativity holds "
                + "in principle; exact-equality auto-sampling fails on IEEE 754 rounding. "
                + "Verify via a finite-only generator (e.g. "
                + "`Gen<Double>.double(in: -1e6...1e6)`) per PropertyLawKit's "
                + "`FloatingPointLaws.swift` posture — kit "
                + "`checkFloatingPointPropertyLaws` covers FP-specific laws (NaN, "
                + "infinity), algebraic associativity needs the finite-only opt-in. "
                + "v1.5+ will surface the generator override automatically."
        }
        return "T = \(stripped) has IEEE 754 floating-point storage. Associativity "
            + "holds in principle; exact-equality auto-sampling fails on rounding. "
            + "Verify via a finite-only generator (e.g. "
            + "`Gen<Double>.double(in: -1e6...1e6)` lifted into \(stripped)) per "
            + "PropertyLawKit's `FloatingPointLaws.swift` tolerance posture. v1.5+ "
            + "will surface the generator override automatically."
    }
}
