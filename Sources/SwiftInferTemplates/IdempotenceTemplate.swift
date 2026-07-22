import SwiftInferCore

/// Idempotence template — `f: T -> T` where applying `f` twice equals
/// applying it once. The simplest M1 template: single-function, no
/// pairing, scoring drawn from PRD §4 + §5.2.
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

    /// Curated idempotence-verb list per PRD §5.2. Project-vocabulary
    /// extension (§4.5's `idempotenceVerbs` from `vocabulary.json`) lands
    /// at M2; for M1.3 the list is the curated set, exact-match only.
    public static let curatedVerbs: Set<String> = [
        // Base (free/mutating-stem) and past-participle (non-mutating instance)
        // spellings both listed — Swift names the pure transform as the
        // participle (`x.normalized()`), which the B32 instance self-form now
        // surfaces. Mirrors InvolutionTemplate's dual base/participle listing.
        "normalize", "normalized",
        "canonicalize", "canonicalized",
        "trim", "trimmed",
        "flatten", "flattened",
        "sort", "sorted",
        "deduplicate", "deduplicated",
        "sanitize", "sanitized",
        "format", "formatted"
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
    /// V1.39.B — migrated to the Constraint Engine (PRD §20.2).
    /// Behavior preserved bit-for-bit (existing IdempotenceTemplate test
    /// suite + V1.39.D equivalence tests).
    public static func suggest(
        for summary: FunctionSummary,
        vocabulary: Vocabulary = .empty,
        inheritedTypesByName: [String: Set<String>] = [:],
        carrierKindResolver: CarrierKindResolver? = nil
    ) -> Suggestion? {
        ConstraintRunner.suggest(
            constraint: makeConstraint(
                vocabulary: vocabulary,
                inheritedTypesByName: inheritedTypesByName,
                carrierKindResolver: carrierKindResolver
            ),
            subject: summary
        )
    }

    /// V1.39.B — Constraint factory.
    public static func makeConstraint(
        vocabulary: Vocabulary,
        inheritedTypesByName: [String: Set<String>],
        carrierKindResolver: CarrierKindResolver?
    ) -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "idempotence",
            appliesTo: { summary in
                Self.typeSymmetrySignal(for: summary) != nil
            },
            signals: { summary in
                Self.accumulatedSignals(
                    for: summary,
                    vocabulary: vocabulary,
                    inheritedTypesByName: inheritedTypesByName,
                    carrierKindResolver: carrierKindResolver
                )
            },
            evidence: { summary in [summary.inferenceEvidence] },
            identity: Self.makeIdentity(for:),
            carrier: { $0.containingTypeName },
            // V1.149 — the generator carrier is the parameter type `T`, not
            // the owning type. `typeSymmetrySignal` only fires when
            // `param.typeText == returnTypeText`, so `returnTypeText` is `T`
            // and is always present here. For a method defined on `T`
            // (`extension Int`) this equals `carrier` and is a no-op; for a
            // `static`/free function over a parameter it's the fix that lets
            // verify derive `Gen<T>` while still calling `Owner.f(_:)`.
            carrierType: { $0.returnTypeText },
            caveats: { _ in Self.makeCaveats() }
        )
    }

    /// V1.39.B — preserves the pre-migration signal-accumulation order.
    /// Split into name- and veto-side helpers to keep each function
    /// within SwiftLint's cyclomatic_complexity cap.
    static func accumulatedSignals(
        for summary: FunctionSummary,
        vocabulary: Vocabulary,
        inheritedTypesByName: [String: Set<String>],
        carrierKindResolver: CarrierKindResolver?
    ) -> [Signal] {
        guard let typeSymmetry = typeSymmetrySignal(for: summary) else {
            return []
        }
        var signals: [Signal] = [typeSymmetry]
        signals.append(contentsOf: nameSideSignals(for: summary, vocabulary: vocabulary))
        signals.append(contentsOf: vetoSideSignals(
            for: summary,
            inheritedTypesByName: inheritedTypesByName,
            carrierKindResolver: carrierKindResolver
        ))
        return signals
    }

    private static func nameSideSignals(
        for summary: FunctionSummary,
        vocabulary: Vocabulary
    ) -> [Signal] {
        var signals: [Signal] = []
        if let name = nameSignal(for: summary, vocabulary: vocabulary) {
            signals.append(name)
        }
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
        if let docstring = docstringCorroborationSignal(for: summary) {
            signals.append(docstring)
        }
        return signals
    }

    private static func vetoSideSignals(
        for summary: FunctionSummary,
        inheritedTypesByName: [String: Set<String>],
        carrierKindResolver: CarrierKindResolver?
    ) -> [Signal] {
        var signals: [Signal] = []
        if let setAlgebra = setAlgebraShapeVeto(for: summary) {
            signals.append(setAlgebra)
        }
        if let mathForward = mathForwardFunctionVeto(for: summary) {
            signals.append(mathForward)
        }
        if let shapeVeto = shapeDisambiguationVeto(for: summary) {
            signals.append(shapeVeto)
        }
        if let carrier = carrierKindResolver?.carrierKindSignal(
            forContainingTypeName: summary.containingTypeName
        ) {
            signals.append(carrier)
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

    /// V1.39.B — caveat list (2 constant entries).
    static func makeCaveats() -> [String] {
        [
            "T must conform to Equatable for the emitted property to compile. "
                + "SwiftInfer M1 does not verify protocol conformance — confirm before applying.",
            "If T is a class with a custom ==, the property is over value equality as T.== defines it."
        ]
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
}

// V1.43 cleanup — signals/vetoes/builders live here so the primary
// enum body stays under SwiftLint's type_body_length cap.
extension IdempotenceTemplate {

    // MARK: - Signals

    private static func typeSymmetrySignal(for summary: FunctionSummary) -> Signal? {
        guard !summary.isMutating,
              let returnType = summary.returnTypeText,
              returnType != "Void",
              returnType != "()" else {
            return nil
        }
        // Free / static: exactly one non-`inout` parameter whose type is the
        // return type — `func normalize(_ x: T) -> T`.
        if summary.parameters.count == 1,
           let param = summary.parameters.first,
           !param.isInout,
           returnType == param.typeText {
            return Signal(
                kind: .typeSymmetrySignature,
                weight: 30,
                detail: "Type-symmetry signature: T -> T (T = \(returnType))"
            )
        }
        // Optional-narrowing free / static form — `func mergedWith(_ x: T?) -> T`.
        // (See IdempotenceTemplate+OptionalNarrowing.swift.)
        if let optionalSignal = optionalNarrowingSignal(returnType: returnType, summary: summary) {
            return optionalSignal
        }
        // Instance: zero parameters, returning the containing type —
        // `func normalized() -> Doc` (`self -> Self`). B32 — mirrors
        // InvolutionTemplate's two-shape acceptance so instance idempotent
        // transforms surface, not only the free `f(x)` form. `self` is the
        // operand; `Array`-materialised wrapper returns remain out of scope.
        //
        // The return may be written as the literal `Self` (`var canonicalizedTransform:
        // Self`, `func normalized() -> Self`) — canonicalize it to the container, the
        // same way DualStylePairing / SetAlgebraShape / the binary-op type-symmetry
        // signal already do. Return-position only, and only on the NULLARY self-form,
        // so the binary `merge(_ other: Self)` x-curried-idempotence hazard is untouched.
        if summary.parameters.isEmpty,
           let container = summary.containingTypeName,
           container == returnType || returnType == "Self" {
            let resolved = returnType == "Self" ? container : returnType
            return Signal(
                kind: .typeSymmetrySignature,
                weight: 30,
                detail: "Type-symmetry signature: self -> Self (Self = \(resolved))"
            )
        }
        return nil
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
        // V1.25.A — name-prefix gated magnitude bump. When the function
        // name starts with an index-advance prefix (`index*`, `bucket*`,
        // `word*`), the joint match (direction-label + index-advance
        // name) is high-confidence non-idempotent — bump -15 → -25 (full
        // veto-equivalent). Closes the cycle-21 finding: 13+ OC
        // `index(after:)`/`index(before:)` direction-op idempotence
        // rejects dominate the residual idempotence non-lifted pool.
        // Cycle-21 finding doc: identified post-v1.24 as the next
        // priority.
        let name = summary.name
        let isIndexAdvanceName = name.hasPrefix("index")
            || name.hasPrefix("bucket")
            || name.hasPrefix("word")
        if isIndexAdvanceName {
            return Signal(
                kind: .directionLabel,
                weight: -25,
                detail: "Index-advance direction-label: '\(name)(\(label):)' — "
                    + "name-prefix + direction-label joint match identifies "
                    + "positional cursor advance, not a fixed-point operation; "
                    + "lifted shadow not idempotent"
            )
        }
        return Signal(
            kind: .directionLabel,
            weight: -15,
            detail: "Direction-label argument: '\(label)' — function is likely "
                + "directional (increment/decrement) rather than idempotent"
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
        let caveats: [String] = [
            "T must conform to Equatable for the emitted property to compile. "
                + "SwiftInfer M1 does not verify protocol conformance — confirm before applying.",
            "If T is a class with a custom ==, the property is over value equality as T.== defines it."
        ]
        return ExplainabilityBlock(whySuggested: whySuggested, whyMightBeWrong: caveats)
    }
}
