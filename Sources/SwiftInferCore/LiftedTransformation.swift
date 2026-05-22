/// V1.19.B — metadata-only "lift" of a mutating member into the pure
/// shadow form `func op'(_ self: T, params...) -> T`. Consumed by
/// `IdempotenceTemplate`, `IdentityElementPairing`, `InversePairTemplate`,
/// and the new `CompositionTemplate` to re-admit the entire `mutating
/// func` surface to the algebraic-property scoring pipeline that pre-v1.19
/// gated on `!summary.isMutating`.
///
/// The lift is **purely metadata** — no codegen, no source rewrite. The
/// shadow form is only described to the templates so they can score
/// against it; the rendered property body uses the original mutating
/// method against a `var copy` of the input value.
///
/// **Soundness precondition: value semantics on the carrier.** Without
/// `T` being value-semantic, `var copy = self` aliases shared state and
/// the algebraic laws don't hold. v1.18.A's `valueSemanticCarrier` signal
/// is the structural precondition. Per the v1.19 plan open decision #2
/// (carry-forward of the v1.18 plan #2 lean): admission is **strict** —
/// only `CarrierKind.valueSemantic` carriers admit the lift. `.mixed`
/// and `.unknown` carriers do NOT admit. v1.20 measurement may relax to
/// permissive at v1.21 if recall is too low.
///
/// **Naming disambiguation.** This type is unrelated to TestLifter's
/// `LiftedSuggestion` (a Suggestion lifted FROM a test body). This is a
/// `FunctionSummary` lifted INTO the form a non-mutating template can
/// score against. The two concepts share the "lift" verb but operate on
/// different inputs and feed different consumers.
public struct LiftedTransformation: Sendable, Equatable {

    /// The original mutating method this lift was derived from. Always
    /// satisfies `originalSummary.isMutating == true` and
    /// `originalSummary.containingTypeName != nil` per the admission
    /// gate in `LiftedTransformation.derive(from:carrierKindResolver:)`.
    public let originalSummary: FunctionSummary

    /// The carrier type — `originalSummary.containingTypeName!`.
    /// Captured here for direct access without re-unwrapping the
    /// optional. Always classifies as `.valueSemantic` per the
    /// strict admission gate.
    public let carrier: String

    /// The lift's pure-function parameter list — `(self: T, params...)`.
    /// The first entry is always the implicit-self binding (no label,
    /// internal name `self`, type `carrier`, non-`inout`); subsequent
    /// entries mirror `originalSummary.parameters` verbatim. Templates
    /// that need to reason about the original parameters skip
    /// `liftedParameters[0]` and consume the rest.
    public let liftedParameters: [Parameter]

    /// The lift's return type — always `carrier`. Captured for parallel
    /// access pattern with `originalSummary.returnTypeText`; the
    /// shadow form's body is `{ var c = self; c.<name>(params...);
    /// return c }` regardless of the original `Void` / non-`Void`
    /// return.
    public let liftedReturnType: String

    /// Single-line rationale rendered into the §4.5 explainability
    /// `whySuggested` block: `"Lifted from `mutating func
    /// <Carrier>.<name>(...)`. Property holds iff `<Carrier>` has value
    /// semantics — `var copy = original; copy.<name>(...)` does not
    /// alias original's state."`
    public let rationale: String

    public init(
        originalSummary: FunctionSummary,
        carrier: String,
        liftedParameters: [Parameter],
        liftedReturnType: String,
        rationale: String
    ) {
        self.originalSummary = originalSummary
        self.carrier = carrier
        self.liftedParameters = liftedParameters
        self.liftedReturnType = liftedReturnType
        self.rationale = rationale
    }

    /// Derive the corpus-wide lifted-transformation set from a flat
    /// `FunctionSummary` array, gated by `CarrierKindResolver`. Built
    /// once per `TemplateRegistry.discover` call alongside the existing
    /// `EquatableResolver` / `inheritedTypesByName` / `CarrierKindResolver`
    /// passes; the resulting array is threaded into per-template
    /// `suggest` invocations in V1.19.B–D.
    ///
    /// **Strict admission gate (v1.19 plan open decision #2):** admits
    /// only summaries where:
    ///
    ///   - `summary.isMutating == true`
    ///   - `summary.containingTypeName != nil`
    ///   - `carrierKindResolver.classify(typeName: summary.containingTypeName)
    ///     == .valueSemantic`
    ///
    /// Returns the admitted lifts in source order (file path → line) for
    /// byte-stable output per PRD §16 #6.
    public static func derive(
        from summaries: [FunctionSummary],
        carrierKindResolver: CarrierKindResolver
    ) -> [Self] {
        summaries
            .compactMap { summary in
                lift(summary, carrierKindResolver: carrierKindResolver)
            }
            .sorted(by: lessThan)
    }

    /// Lift a single summary, or return `nil` when the admission gate
    /// rejects it. Public for unit-test access; production callers go
    /// through `derive(from:carrierKindResolver:)`.
    public static func lift(
        _ summary: FunctionSummary,
        carrierKindResolver: CarrierKindResolver
    ) -> Self? {
        guard summary.isMutating,
              let carrier = summary.containingTypeName else {
            return nil
        }
        guard carrierKindResolver.classify(typeName: carrier) == .valueSemantic else {
            return nil
        }
        let selfBinding = Parameter(
            label: nil,
            internalName: "self",
            typeText: carrier,
            isInout: false
        )
        let liftedParameters = [selfBinding] + summary.parameters
        let labels = summary.parameters.map { ($0.label ?? "_") + ":" }.joined()
        let rationale =
            "Lifted from `mutating func \(carrier).\(summary.name)(\(labels))`. "
            + "Property holds iff `\(carrier)` has value semantics — "
            + "`var copy = original; copy.\(summary.name)(...)` does not alias "
            + "original's state."
        return Self(
            originalSummary: summary,
            carrier: carrier,
            liftedParameters: liftedParameters,
            liftedReturnType: carrier,
            rationale: rationale
        )
    }

    private static func lessThan(
        _ lhs: Self,
        _ rhs: Self
    ) -> Bool {
        let lhsLoc = lhs.originalSummary.location
        let rhsLoc = rhs.originalSummary.location
        if lhsLoc.file != rhsLoc.file {
            return lhsLoc.file < rhsLoc.file
        }
        return lhsLoc.line < rhsLoc.line
    }
}
