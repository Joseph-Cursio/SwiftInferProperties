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
                Self.typeShapeSignal(for: summary) != nil
            },
            signals: { summary in
                Self.accumulatedSignals(
                    for: summary,
                    vocabulary: vocabulary,
                    inheritedTypesByName: inheritedTypesByName
                )
            },
            evidence: { summary in
                [Self.makeEvidence(summary)]
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
        guard let typeShape = typeShapeSignal(for: summary) else {
            return []
        }
        var signals: [Signal] = [typeShape]
        if let name = nameSignal(for: summary, vocabulary: vocabulary) {
            signals.append(name)
        }
        if let counter = antiCommutativitySignal(for: summary, vocabulary: vocabulary) {
            signals.append(counter)
        }
        if let fpCounter = floatingPointStorageCounterSignal(for: summary) {
            signals.append(fpCounter)
        }
        if let veto = nonDeterministicVeto(for: summary) {
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

    /// V1.4.3 — fires when the candidate's parameter type is a
    /// curated IEEE 754 floating-point-storage name. Drops Score 30 →
    /// 20 (Possible-tier floor) so the explainability kit-pointer
    /// stays visible under `--include-possible`. Mirrors
    /// AssociativityTemplate.floatingPointStorageCounterSignal.
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
                + "commutativity is not bit-exact under IEEE 754 sampling on edge values"
        )
    }

    /// V1.4.3 — type-aware FP advisory paralleling
    /// AssociativityTemplate.floatingPointAdvisory. `nil` when T isn't
    /// FP-storage; caller skips the FP caveat in that case.
    private static func floatingPointAdvisory(for summary: FunctionSummary) -> String? {
        guard let first = summary.parameters.first,
              FloatingPointStorageNames.contains(first.typeText) else {
            return nil
        }
        let stripped = FloatingPointStorageNames.strippingGenericParameters(first.typeText)
        if FloatingPointStorageNames.isKitSupported(first.typeText) {
            return "T = \(stripped) conforms to FloatingPoint. Commutativity holds "
                + "in principle; exact-equality auto-sampling fails on IEEE 754 NaN "
                + "edge cases (`NaN == NaN` is false). Verify via a finite-only "
                + "generator (e.g. `Gen<Double>.double(in: -1e6...1e6)`) per "
                + "PropertyLawKit's `FloatingPointLaws.swift` posture — kit "
                + "`checkFloatingPointPropertyLaws` covers NaN-domain laws "
                + "separately, algebraic commutativity needs the finite-only "
                + "opt-in. v1.5+ will surface the generator override automatically."
        }
        return "T = \(stripped) has IEEE 754 floating-point storage. Commutativity "
            + "holds in principle; exact-equality auto-sampling fails on NaN edge "
            + "cases. Verify via a finite-only generator (e.g. "
            + "`Gen<Double>.double(in: -1e6...1e6)` lifted into \(stripped)) per "
            + "PropertyLawKit's `FloatingPointLaws.swift` tolerance posture. v1.5+ "
            + "will surface the generator override automatically."
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
