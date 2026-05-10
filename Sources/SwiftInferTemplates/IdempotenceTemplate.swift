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
    ///
    /// `vocabulary` is the project-extensible naming layer per PRD §4.5;
    /// the template consults `vocabulary.idempotenceVerbs` alongside the
    /// curated list. Defaults to `.empty` so M1 call sites compile
    /// unchanged.
    ///
    /// V1.5.2 — `inheritedTypesByName` feeds the protocol-coverage
    /// veto. Idempotence on a `: SetAlgebra` type is covered by
    /// `setIntersectionIdempotent` (kit
    /// `checkSetAlgebraPropertyLaws`); idempotence on a kit
    /// `: Semilattice` type is covered by `semilatticeIdempotence`
    /// (kit `checkSemilatticePropertyLaws`). Other types fall through
    /// — generic `f(f(x)) == f(x)` doesn't have a one-to-one stdlib
    /// protocol mapping, so the template stays surfaced.
    public static func suggest(
        for summary: FunctionSummary,
        vocabulary: Vocabulary = .empty,
        inheritedTypesByName: [String: Set<String>] = [:],
        carrierKindResolver: CarrierKindResolver? = nil
    ) -> Suggestion? {
        guard let typeSymmetry = typeSymmetrySignal(for: summary) else {
            return nil
        }
        var signals: [Signal] = [typeSymmetry]
        if let name = nameSignal(for: summary, vocabulary: vocabulary) {
            signals.append(name)
        }
        // V1.22.C — fixed-point-name positive signal (recall-positive).
        // First positive signal in the post-V1.4.3 era; introduces accepts
        // on lower-confidence idempotence names not in V1.4.1 curatedVerbs.
        if let fixedPoint = fixedPointNameSignal(for: summary) {
            signals.append(fixedPoint)
        }
        if let composition = selfCompositionSignal(for: summary) {
            signals.append(composition)
        }
        if let direction = directionLabelCounterSignal(for: summary) {
            signals.append(direction)
        }
        if let domainMarker = domainMarkerCounterSignal(for: summary) {
            signals.append(domainMarker)
        }
        if let setAlgebra = setAlgebraShapeVeto(for: summary) {
            signals.append(setAlgebra)
        }
        // V1.21.C — math-library forward-function veto (3-cycle carry-
        // forward; closes the CM elementary-functions noise class
        // measured at 0/3 = 0% in cycle-17).
        if let mathForward = mathForwardFunctionVeto(for: summary) {
            signals.append(mathForward)
        }
        if let carrier = carrierKindResolver?.carrierKindSignal(
            forContainingTypeName: summary.containingTypeName
        ) {
            signals.append(carrier)
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

    static func nameSignal(
        for summary: FunctionSummary,
        vocabulary: Vocabulary
    ) -> Signal? {
        // Curated takes precedence over project vocabulary so a verb
        // already in the curated list never double-fires when the project
        // happens to repeat it. Both contribute the same +40 weight per
        // PRD §4.5; only the rendered detail line distinguishes them.
        if curatedVerbs.contains(summary.name) {
            return Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Curated idempotence verb match: '\(summary.name)'"
            )
        }
        if vocabulary.idempotenceVerbs.contains(summary.name) {
            return Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Project-vocabulary idempotence verb match: '\(summary.name)'"
            )
        }
        return nil
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

    /// V1.10.1 — fires when the candidate's first-parameter argument label
    /// is in `DirectionLabels.curated` (e.g., `index(after:)`,
    /// `bucket(before:)`). Emits weight `-15` so type-symmetry's `+30`
    /// collapses to `+15` → Suppressed tier (< 20). Curated-verb matches
    /// add `+40` and override (net `+55` → Likely tier preserved). Closes
    /// the cycle-6 0/10 idempotence rejection pattern's dominant 5-of-10
    /// sub-pattern.
    ///
    /// **V1.13.1.** Hoisted out of `IdempotenceTemplate.directionLabels`
    /// to `SwiftInferCore.DirectionLabels.curated` once round-trip became
    /// the third consumer in cycle 9. See `DirectionLabels` for the
    /// historical motivation.
    static func directionLabelCounterSignal(
        for summary: FunctionSummary
    ) -> Signal? {
        guard let label = summary.parameters.first?.label,
              DirectionLabels.curated.contains(label) else {
            return nil
        }
        return Signal(
            kind: .directionLabel,
            weight: -15,
            detail: "Direction-label argument: '\(label)' — function is likely "
                + "directional (increment/decrement) rather than idempotent"
        )
    }

    static func nonDeterministicVeto(for summary: FunctionSummary) -> Signal? {
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

    /// V1.5.2 — fires when the candidate type already conforms to a
    /// protocol whose published laws cover the idempotence property
    /// the template would emit. Candidate properties span
    /// `setIntersectionIdempotent` (covered by SetAlgebra) +
    /// `semilatticeIdempotence` (covered by kit Semilattice). Generic
    /// `f(f(x))` on arbitrary types isn't covered — the veto fires
    /// only when the type's conformance set intersects the curated
    /// idempotence-bearing protocols.
    static func protocolCoverageVeto(
        for summary: FunctionSummary,
        inheritedTypesByName: [String: Set<String>]
    ) -> Signal? {
        ProtocolCoverageMap.coverageVetoSignal(
            forTypeText: summary.parameters.first?.typeText,
            inheritedTypesByName: inheritedTypesByName,
            candidateProperties: [.setIntersectionIdempotent, .semilatticeIdempotence]
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
            "If T is a class with a custom ==, the property is over value equality as T.== defines it."
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
