/// Opaque mock-inferred generator metadata attached to a `Suggestion`
/// whose `generator.source == .inferredFromTests` (TestLifter M4.3).
/// Carries the argument-spec the M4.4 accept-flow renderer uses to
/// emit a `Gen<T> { T(label: <Gen<...>>.run(), ...) }` stub body.
///
/// `nil` for every Suggestion source other than `.inferredFromTests`
/// — the field on `Suggestion` is `mockGenerator: MockGenerator?` with
/// default `nil`, so existing call sites are unchanged.
///
/// **Why a Core-side type rather than a TestLifter-side type:** mirrors
/// the `LiftedOrigin` placement decision (M3.0). The `Suggestion`
/// record itself lives in `SwiftInferCore`, and the downstream
/// renderer / accept-flow / drift / baseline consumers all see
/// `Suggestion`. Putting `MockGenerator` in Core lets the field hang
/// off `Suggestion` without forcing `SwiftInferCore` to depend on
/// `SwiftInferTestLifter` (which would be a layering inversion). The
/// field is opaque to Core — Core never reads it; only
/// `SwiftInferCLI`'s accept-flow renderer does.
public struct MockGenerator: Sendable, Equatable {

    /// One argument slot in the synthesized `T(...)` constructor call.
    /// `swiftTypeName` is a Swift type identifier ("Int", "String",
    /// "Bool", "Double") the M4.4 renderer wraps directly as
    /// `Gen<\(swiftTypeName)>`. Storing the Swift type name (rather
    /// than a TestLifter-side `ParameterizedValue.Kind` enum) avoids a
    /// layering dep from Core onto TestLifter and gives the renderer
    /// the exact string it needs.
    public struct Argument: Sendable, Equatable {

        /// `nil` for positional / unlabeled arguments; otherwise the
        /// label as written in the observed test sites.
        public let label: String?

        /// Swift type name the renderer wraps with `Gen<...>`.
        /// "Int" / "String" / "Bool" / "Double" through M4 — the four
        /// literal kinds the slicer's `ParameterizedValue.Kind`
        /// classifies. Future patterns (collections, optionals) extend
        /// the value range; the Suggestion / renderer surface stays
        /// the same.
        public let swiftTypeName: String

        /// Verbatim literal texts observed across the construction
        /// sites that contributed to this argument slot. Preserved for
        /// OD #5's potential "use observed literals" generator path
        /// (currently the M4.4 renderer ignores this and uses
        /// `Gen<\(swiftTypeName)>` per OD #5 default `(a)`); also
        /// useful for M9's inferred-domain detection.
        public let observedLiterals: [String]

        public init(label: String?, swiftTypeName: String, observedLiterals: [String]) {
            self.label = label
            self.swiftTypeName = swiftTypeName
            self.observedLiterals = observedLiterals
        }
    }

    /// The constructed type — what the rendered `Gen<T> { T(...) }`
    /// stub's `T` will be.
    public let typeName: String

    /// Argument spec in canonical (sorted-by-label-then-kind) order —
    /// matches the source `ConstructionShape`'s argument order so the
    /// renderer emits arguments in the same canonical sort.
    public let argumentSpec: [Argument]

    /// Number of test-site constructions that contributed to this
    /// generator. Surfaced in the M4.4 accept-flow's provenance
    /// comment ("Mock-inferred from N construction sites in test
    /// bodies — low confidence").
    public let siteCount: Int

    /// TestLifter M9.0 — per-position inferred-precondition hints.
    /// Default empty so M4-era call sites compile unchanged.
    /// Populated by the M9.2 pipeline wiring (`PreconditionInferrer.
    /// infer(from:)`); surfaced by the M9.2 accept-flow renderer as
    /// `// Inferred precondition:` provenance comment lines above
    /// each affected argument's generator expression.
    public let preconditionHints: [PreconditionHint]

    public init(
        typeName: String,
        argumentSpec: [Argument],
        siteCount: Int,
        preconditionHints: [PreconditionHint] = []
    ) {
        self.typeName = typeName
        self.argumentSpec = argumentSpec
        self.siteCount = siteCount
        self.preconditionHints = preconditionHints
    }
}
