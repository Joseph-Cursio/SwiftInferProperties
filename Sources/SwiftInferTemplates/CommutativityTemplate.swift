import SwiftInferCore

/// Commutativity template — `f: (T, T) -> T` where applying `f` to two
/// arguments in either order yields the same result. Single-function
/// template (no cross-function pairing); scoring drawn from PRD
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

    /// Curated commutativity-verb list per PRD §4 / §5.2. Project
    /// vocabulary entries (`commutativityVerbs` from `vocabulary.json`)
    /// are consulted alongside this list at the same +40 weight per
    /// PRD §4.5; curated takes precedence so a project repeating a
    /// curated entry never double-fires.
    public static let curatedVerbs: Set<String> = [
        "add",
        "combine",
        "merge",
        "union",
        // `intersect` was a stale stem — the stdlib SetAlgebra method is
        // `intersection` (non-mutating), which never matched it. `intersection`
        // and `symmetricDifference` are genuinely commutative (a∩b == b∩a,
        // a△b == b△a); the B29 order-sensitive-carrier veto still guards the
        // `OrderedSet`/`Array` case where `==` compares order. Added from the
        // swift-collections `876177db` historical backtest — the pre-fix
        // `symmetricDifference` was `subtracting` in disguise (non-commutative),
        // and this is what lets commutativity + verify catch that class of bug.
        "intersect",
        "intersection",
        "symmetricDifference"
    ]

    /// Curated anti-commutativity-verb list per PRD §4.1's -30
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
        "concatenated",
        // Participle / gerund forms — the non-mutating instance spelling
        // (`x.subtracting(y)`, `x.appending(y)`) that the 2026-07 instance-op
        // recall widening now surfaces. Same asymmetric semantics as their bare
        // stems above; without these the widened detector would Possible-fire
        // commutativity on `Set.subtracting` / `Array.appending`.
        "subtracting",
        "dividing",
        "appending",
        "prepending"
    ]

    /// B29 — set-combination verbs whose commutativity is a *semilattice* law:
    /// true under set equality, but FALSE on an order-sensitive carrier whose
    /// `==` compares element order (`OrderedSet` / `Array` / …), because the
    /// operation preserves insertion order. `orderSensitiveCarrierVetoSignal`
    /// suppresses a commutativity suggestion for these verbs on such carriers.
    public static let setCombinationVerbs: Set<String> = [
        "union",
        "intersection",
        "intersect",
        "symmetricDifference"
    ]

    /// Build a suggestion for `summary`, or return `nil` if the type
    /// pattern doesn't match or the score collapses to `.suppressed`.
    ///
    /// V1.5.2 — `inheritedTypesByName` feeds the protocol-coverage
    /// veto. Op-class-aware: `+` on a `: AdditiveArithmetic` type maps
    /// to `additiveCommutative` (kit `checkAdditiveArithmeticPropertyLaws`);
    /// `*` on a `: Numeric` type maps to `multiplicativeCommutative`
    /// (kit `checkNumericPropertyLaws`); `union` / `formUnion` on a
    /// `: SetAlgebra` type maps to `setUnionCommutative` (kit
    /// `checkSetAlgebraPropertyLaws`). User-named ops (`combine`,
    /// `merge`, etc.) on Numeric types fall through unsuppressed —
    /// the kit covers `+` / `*` specifically, not arbitrary
    /// commutative functions on Numeric carriers.
    /// V1.36.C — migrated to the Constraint Engine (PRD §20.2). The
    /// template now expresses itself as a `Constraint<FunctionSummary>`
    /// via `makeConstraint(vocabulary:inheritedTypesByName:)`, and
    /// `suggest(for:)` is a thin wrapper that orchestrates the
    /// constraint through `ConstraintRunner.suggest`. Behavior is
    /// preserved bit-for-bit (verified by
    /// `CommutativityConstraintEquivalenceTests`).
    public static func suggest(
        for summary: FunctionSummary,
        vocabulary: Vocabulary = .empty,
        inheritedTypesByName: [String: Set<String>] = [:]
    ) -> Suggestion? {
        let constraint = makeConstraint(
            vocabulary: vocabulary,
            inheritedTypesByName: inheritedTypesByName
        )
        return ConstraintRunner.suggest(constraint: constraint, subject: summary)
    }

    /// V1.36.C — Constraint factory. Captures the runtime
    /// `vocabulary` + `inheritedTypesByName` inputs into the
    /// constraint's @Sendable closures. The constraint is recreated
    /// per-call rather than memoised; this matches the existing
    /// per-call behaviour and keeps the v1.36 migration scope narrow.
    /// Future cycles can cache constraints if profiling motivates.
    public static func makeConstraint(
        vocabulary: Vocabulary,
        inheritedTypesByName: [String: Set<String>]
    ) -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "commutativity",
            appliesTo: { summary in
                summary.binaryOperatorTypeSymmetrySignal != nil
            },
            signals: { summary in
                Self.accumulatedSignals(
                    for: summary,
                    vocabulary: vocabulary,
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

    /// V1.36.C — accumulates all signals in the same order the
    /// pre-migration bespoke `suggest(for:)` did. Helper kept package-
    /// internal (not file-private) so equivalence-test fixtures can
    /// drive it directly without going through the runner.
    static func accumulatedSignals(
        for summary: FunctionSummary,
        vocabulary: Vocabulary,
        inheritedTypesByName: [String: Set<String>]
    ) -> [Signal] {
        guard let typeShape = summary.binaryOperatorTypeSymmetrySignal else {
            return []
        }
        var signals: [Signal] = [typeShape]
        let name = nameSignal(for: summary, vocabulary: vocabulary)
        if let name {
            signals.append(name)
        }
        let anti = antiCommutativitySignal(for: summary, vocabulary: vocabulary)
        if let anti {
            signals.append(anti)
        }
        // Corroborate-only (+15): a documented commutative op. Also counts as the
        // corroboration the B24 unsupported-shape counter below demands.
        let docstring = docstringCorroborationSignal(for: summary)
        if let docstring {
            signals.append(docstring)
        }
        // B29 — a set-combination commutativity law is order-dependent; on an
        // order-sensitive carrier it is genuinely false (`a.union(b)` and
        // `b.union(a)` differ in order under the carrier's `==`). Veto rather
        // than counter-weight: it is wrong, not low-confidence.
        if let orderVeto = orderSensitiveCarrierVetoSignal(for: summary) {
            signals.append(orderVeto)
        }
        // B24 — a shape-only candidate with neither a commutative name nor an
        // anti-commutativity name has nothing corroborating that its `(T,T)->T`
        // shape is a commutative op. Suppress it; the anti path already handles
        // the names it recognizes, and `+`/`*` plus the semilattice/order verbs
        // (join/meet/min/max/gcd/lcm) are canonically commutative.
        let hasOperator = AssociativityTemplate.knownAlgebraicOperators.contains(summary.name)
        let hasAlgebraicVerb = AssociativityTemplate.commutativeAssociativeVerbs.contains(summary.name)
        if name == nil, anti == nil, docstring == nil, !hasOperator, !hasAlgebraicVerb,
           let unsupported = unsupportedShapeCounterSignal(for: summary) {
            signals.append(unsupported)
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

    /// V1.36.C — caveat list builder used by `makeConstraint`. The
    /// runner's default `makeExplainability` appends these to the
    /// emitted Suggestion's `whyMightBeWrong`. Format preserves the
    /// pre-migration bespoke `makeExplainability` order: base
    /// caveats first, FP advisory last when applicable.
    static func makeCaveats(for summary: FunctionSummary) -> [String] {
        var caveats: [String] = [
            "T must conform to Equatable for the emitted property to compile. "
                + "SwiftInfer M1 does not verify protocol conformance — confirm before applying.",
            "If T is a class with a custom ==, the property is over value equality as T.== defines it."
        ]
        if let fpCaveat = floatingPointAdvisory(for: summary) {
            caveats.append(fpCaveat)
        }
        return caveats
    }

    /// Canonical hash input per PRD §7.5: `template ID | canonical
    /// signature`. Reuses `IdempotenceTemplate.canonicalSignature`'s
    /// stable form (`Container.name(label1:label2:)|(T1,T2)->R`) so
    /// suggestion identities for the same function under different
    /// templates are namespaced by the leading template ID.
    private static func makeIdentity(for summary: FunctionSummary) -> SuggestionIdentity {
        SuggestionIdentity(canonicalInput: "commutativity|" + IdempotenceTemplate.canonicalSignature(of: summary))
    }
}

// V1.43 cleanup — signals/vetoes/builders live here so the primary
// enum body stays under SwiftLint's type_body_length cap.
extension CommutativityTemplate {

    // MARK: - Signals

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

    /// B29 — veto for a set-combination commutativity suggestion on an
    /// order-sensitive carrier. `union` / `intersection` are commutative as a
    /// *set* semilattice, but `OrderedSet` / `Array` / … compare element order
    /// in `==`, so `a.union(b) == b.union(a)` is false there (it holds only
    /// under an order-insensitive comparison such as `isEqualSet`). The carrier
    /// (`containingTypeName`) is matched against the curated
    /// `OrderSensitiveCarrierNames` denylist — the pre-SemanticIndex stand-in
    /// for detecting an order-sensitive `==` structurally. Associativity and
    /// idempotence are NOT vetoed: both hold on these carriers (order-preserving
    /// append is associative; `x ∪ x == x`).
    private static func orderSensitiveCarrierVetoSignal(
        for summary: FunctionSummary
    ) -> Signal? {
        guard setCombinationVerbs.contains(summary.name),
              let carrier = summary.containingTypeName,
              OrderSensitiveCarrierNames.contains(carrier) else {
            return nil
        }
        let stripped = OrderSensitiveCarrierNames.strippingGenericParameters(carrier)
        return Signal(
            kind: .orderSensitiveCarrier,
            weight: Signal.vetoWeight,
            detail: "Order-sensitive carrier: \(stripped).== compares element order, so "
                + "'\(summary.name)' is NOT commutative under it — a.\(summary.name)(b) and "
                + "b.\(summary.name)(a) hold the same members in a different order. The "
                + "semilattice commutativity law holds only under an order-insensitive "
                + "comparison such as isEqualSet"
        )
    }

    /// B24 — counter-signal that suppresses a shape-only commutativity candidate.
    /// The caller invokes it only when neither a commutative name nor an
    /// anti-commutativity name matched, so the bare `(T, T) -> T` shape is all
    /// there is — and a correct `backoffDelay` / `weighted` matches that shape
    /// without being commutative. `-20` drops Score 30 → 10, below the Possible
    /// floor; a named commutative op keeps this from firing.
    private static func unsupportedShapeCounterSignal(
        for summary: FunctionSummary
    ) -> Signal? {
        Signal(
            kind: .unsupportedAlgebraicShape,
            weight: -20,
            detail: "'\(summary.name)' matched only the (T, T) -> T shape — no commutative "
                + "name; commutativity is not entailed by the shape alone"
        )
    }

    /// V1.5.2 — fires when the candidate type's existing protocol
    /// conformances cover the commutativity property the template
    /// would emit, mapped op-class-aware: `+` → additive, `*` →
    /// multiplicative, `union`/`formUnion` → set-union. Other ops
    /// don't bind to a kit-published commutativity law (e.g. a
    /// user-named `combine` on Int isn't covered by Numeric's `+`/`*`
    /// commutativity laws), so they fall through unsuppressed.
    private static func protocolCoverageVeto(
        for summary: FunctionSummary,
        inheritedTypesByName: [String: Set<String>]
    ) -> Signal? {
        let candidates = commutativityCoverageCandidates(forOp: summary.name)
        guard !candidates.isEmpty else { return nil }
        return ProtocolCoverageMap.coverageVetoSignal(
            forTypeText: summary.parameters.first?.typeText,
            inheritedTypesByName: inheritedTypesByName,
            candidateProperties: candidates
        )
    }

    /// V1.5.2 — op-class → KnownProperty candidate set for the
    /// commutativity veto. `static internal` so AssociativityTemplate
    /// can reuse the same op-class shape (commutativity / associativity
    /// share the curated verb list per the AssociativityTemplate type
    /// doc).
    static func commutativityCoverageCandidates(forOp opName: String) -> [KnownProperty] {
        switch opName {
        case "+":
            return [.additiveCommutative]

        case "*":
            return [.multiplicativeCommutative]

        case "union", "formUnion":
            return [.setUnionCommutative]

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
        }
        return ExplainabilityBlock(whySuggested: whySuggested, whyMightBeWrong: caveats)
    }
}
