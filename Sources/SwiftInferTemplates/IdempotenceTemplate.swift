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
        "format", "formatted",
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
                Self.typeSymmetrySignal(
                    for: summary,
                    inheritedTypesByName: inheritedTypesByName
                ) != nil
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
            // the owning type. Every arm of `typeSymmetrySignal` returns a
            // signal whose operand type IS `returnTypeText`: the concrete
            // forms because `param.typeText == returnTypeText`, the
            // optional-narrowing form because `T? -> T` is generated at `T`,
            // and the erased self-form because the law is stated over the
            // erased return. So `returnTypeText` is the generator carrier in
            // all four cases and is always present here. For a method defined
            // on `T` (`extension Int`) this equals `carrier` and is a no-op;
            // for a `static`/free function over a parameter it's the fix that
            // lets verify derive `Gen<T>` while still calling `Owner.f(_:)`.
            carrierType: { $0.returnTypeText },
            caveats: { summary in
                Self.makeCaveats(
                    for: summary,
                    inheritedTypesByName: inheritedTypesByName
                )
            },
            generators: Self.makeGenerators(for:)
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
        guard let typeSymmetry = typeSymmetrySignal(
            for: summary,
            inheritedTypesByName: inheritedTypesByName
        ) else {
            return []
        }
        var signals: [Signal] = [typeSymmetry]
        // The author's own claim, in either direction. Kept out of the name- and
        // veto-side helpers because it is neither: it reads a declaration, and it
        // can corroborate or veto from the one field.
        if let declared = declaredEffectSignal(for: summary) {
            signals.append(declared)
        }
        if let inferred = inferredEffectSignal(for: summary) {
            signals.append(inferred)
        }
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
        if let returnShape = returnShapeVeto(for: summary) {
            signals.append(returnShape)
        }
        if let builderVeto = resultBuilderVeto(for: summary) {
            signals.append(builderVeto)
        }
        if let carrier = carrierKindResolver?.carrierKindSignal(
            forContainingTypeName: summary.containingTypeName
        ) {
            signals.append(carrier)
        }
        if let veto = summary.nonDeterministicVetoSignal {
            signals.append(veto)
        }
        if let assumedCoverage = assumedKitCoverage(
            for: summary,
            inheritedTypesByName: inheritedTypesByName
        ) {
            signals.append(assumedCoverage)
        }
        return signals
    }

    /// V1.39.B — caveat list (2 constant entries).
    static func makeCaveats(
        for summary: FunctionSummary? = nil,
        inheritedTypesByName: [String: Set<String>] = [:]
    ) -> [String] {
        var caveats = [
            "T must conform to Equatable for the emitted property to compile. "
                + "This tool does not verify protocol conformance — confirm before applying.",
            "If T is a class with a custom ==, the property is over value equality as T.== defines it.",
        ]
        // The erased self-form owes a caveat the concrete forms do not: the
        // claim is checked on the erasure, so it cannot see a distinction the
        // erased type drops.
        if let summary,
           let carrier = summary.containingTypeName,
           let returnType = summary.returnTypeText,
           erasedSelfFormSignal(
               for: summary,
               inheritedTypesByName: inheritedTypesByName
           ) != nil {
            caveats.append(erasedSelfFormCaveat(carrier: carrier, returnType: returnType))
        }
        if summary?.declaresUnknownEffect == true {
            caveats.append(unknownEffectCaveat)
        }
        return caveats
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
