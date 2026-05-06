/// TestLifter M11.0 — predicate-equivalence-class hint surfaced by the
/// M11.1 `PredicateEquivalenceClassDetector` when a test corpus
/// partitions on `(positive, negative)` method-name markers (per M11
/// plan OD #1, the curated v1.1 marker set is `Valid`/`Invalid` only)
/// and every site in each bucket invokes the same unary predicate with
/// homogeneous polarity. PRD §7.8 third example.
///
/// Unlike `PreconditionHint` (M9) and `DomainHint` (M10), which decorate
/// an existing `MockGenerator` on a constructor / round-trip pair, an
/// equivalence-class hint isn't tied to a pre-existing template
/// suggestion — it's a corpus-level finding about a predicate. M11
/// surfaces it as a stand-alone advisory suggestion in the discover
/// stream (the wiring is M11.2's territory; the data model lands here).
///
/// **Advisory only.** PRD §3.5 conservative bias — the hint never
/// triggers a runnable property emission (rendering it as
/// `forAll(Gen<T>.filter(predicate)) { #expect(predicate($0)) }` would
/// be a tautology); the accept-flow writeout (M11.2) is comment-only at
/// `Tests/Generated/SwiftInfer/EquivalenceClasses_<predicate>.swift`.
/// The user reads the documentation block + authors per-class
/// properties manually using the suggested filter generators.
public struct EquivalenceClassHint: Sendable, Equatable, Codable {

    /// The predicate function name common to every site in both buckets.
    /// Surfaced in the rendered comment ("the predicate `isValid`
    /// partitions ...") and in the suggested generator expressions
    /// (`Gen<T>.filter(isValid)`).
    public let predicateName: String

    /// The type name `T` the equivalence-class generators are over.
    /// Pre-computed by the detector so the renderer doesn't re-derive it
    /// from the predicate's signature.
    public let argTypeName: String

    /// The marker text identifying the positive (asserted-true) bucket.
    /// `"Valid"` in the v1.1 narrowed scope per M11 plan OD #1; reserved
    /// as a field so a future v1.x marker-table-expansion plan can
    /// populate `"Success"` / `"Accept"` / etc. without a model
    /// migration.
    public let positiveMarker: String

    /// The marker text identifying the negative (asserted-false) bucket.
    /// `"Invalid"` in the v1.1 narrowed scope per M11 plan OD #1.
    public let negativeMarker: String

    /// Number of test methods in the positive bucket whose method names
    /// carried `positiveMarker` AND whose sliced bodies asserted the
    /// predicate true. Always `≥ 3` per the M11 plan's per-bucket
    /// threshold (mirrors M4.3 / M9 / M10).
    public let positiveSiteCount: Int

    /// Number of test methods in the negative bucket. Always `≥ 3` per
    /// the per-bucket threshold; both buckets must independently reach
    /// threshold for the hint to emit.
    public let negativeSiteCount: Int

    /// Predicate-shape veto reason when the M11.1 detector flagged the
    /// predicate as ineligible for a `Gen<T>.filter(predicate)` generator
    /// suggestion (per M11 plan OD #2/#3/#4 — same hard-veto rules M10
    /// uses for round-trip-pair producers). `nil` when no veto fired
    /// (the suggested generators apply); non-nil renders the veto reason
    /// in the documentation block + suppresses the generator suggestion.
    public let predicateVeto: PredicateVetoReason?

    /// Recommended Swift expression for the positive (asserted-true)
    /// equivalence class. When `predicateVeto == nil`, this is the
    /// `Gen<T>.filter(predicate)` form the M11.2 renderer surfaces in
    /// the documentation block; when `predicateVeto != nil`, the
    /// renderer omits the generator suggestion and surfaces the veto
    /// reason instead. Pre-computed by the detector.
    public let suggestedPositiveGenerator: String

    /// Recommended Swift expression for the negative (asserted-false)
    /// equivalence class — typically `Gen<T>.filter { !predicate($0) }`.
    /// Same render-or-suppress contract as `suggestedPositiveGenerator`.
    public let suggestedNegativeGenerator: String

    /// TestLifter M13.3 — `true` when the partition syntactically
    /// covers the domain `T` (positive bucket asserts via
    /// `XCTAssertTrue(predicate(x))` AND negative bucket asserts via
    /// `XCTAssertFalse(predicate(x))` for every site, no `!` negation).
    /// `negative = ¬positive` syntactically; the union of buckets
    /// covers `T`. Surfaced in the rendered comment block as the
    /// additional exhaustiveness property: `forAll x: T. p(x) ∨ ¬p(x)`.
    /// Defaults to `false` for back-compat — pre-M13.3 callers / tests
    /// don't need to set the field.
    public let coversDomain: Bool

    public init(
        predicateName: String,
        argTypeName: String,
        positiveMarker: String,
        negativeMarker: String,
        positiveSiteCount: Int,
        negativeSiteCount: Int,
        predicateVeto: PredicateVetoReason?,
        suggestedPositiveGenerator: String,
        suggestedNegativeGenerator: String,
        coversDomain: Bool = false
    ) {
        self.predicateName = predicateName
        self.argTypeName = argTypeName
        self.positiveMarker = positiveMarker
        self.negativeMarker = negativeMarker
        self.positiveSiteCount = positiveSiteCount
        self.negativeSiteCount = negativeSiteCount
        self.predicateVeto = predicateVeto
        self.suggestedPositiveGenerator = suggestedPositiveGenerator
        self.suggestedNegativeGenerator = suggestedNegativeGenerator
        self.coversDomain = coversDomain
    }
}

/// Reasons the M11.1 detector can mark an equivalence-class hint's
/// predicate as ineligible for the `Gen<T>.filter(predicate)` generator
/// suggestion. Hitting any of these surfaces the hint as comment-only
/// documentation (no generator suggestion in the rendered block) — the
/// `swift-property-based` runner cannot shrink through `try!` / `await`,
/// `Gen<_>.filter(_:)` is unary, and a non-generatable predicate-arg
/// type has no path to a `Gen<T>` source.
///
/// Mirrors `DomainHint.ProducerVetoReason` (M10) by design — same shape,
/// same downstream contract.
public enum PredicateVetoReason: Sendable, Equatable, Codable {

    /// Predicate is `throws`. Suggesting `Gen<T>.filter(throwingPredicate)`
    /// would emit code that can't compile (or can't shrink) under the
    /// `swift-property-based` runner.
    case predicateThrows

    /// Predicate is `async`. `Gen<T>.filter(_:)` is a synchronous
    /// transformation; suggesting an async predicate breaks the runner.
    case predicateAsync

    /// Predicate takes more than one argument. `Gen<T>.filter(_:)` is
    /// unary; partial-application is fragile (the corpus may show
    /// variation in the second argument that the user expects to remain
    /// configurable). Defer to the future v1.x M11.1+ general partition
    /// expansion if real corpora show value in this case.
    case predicateMultiArg

    /// Predicate's single argument type is not auto-generatable per the
    /// M3+ `DerivationStrategist` strategy table (the strategist returns
    /// `.todo` or `.userGen`). The user can resolve `.userGen` cases by
    /// providing `static func gen()` themselves and re-running discover;
    /// the hint will then re-fire without the veto.
    case predicateArgNotGeneratable

    /// TestLifter M13.2 — predicate's return type is not `Equatable` per
    /// the `FunctionSummary` introspection (return-type identifier doesn't
    /// match a known Equatable stdlib type or carry an `Equatable`
    /// conformance). Surfaced only by `NClassEquivalenceClassDetector`;
    /// the M11.1 two-class detector never emits this case.
    case predicateReturnNotEquatable

    /// User-facing reason text surfaced in the M11.2 explainability
    /// block + the accept-flow comment-only writeout. Mirrors the
    /// `DomainHint.ProducerVetoReason` advisory-text pattern.
    public var advisoryReason: String {
        switch self {
        case .predicateThrows:
            return "predicate throws — Gen<T>.filter cannot apply throwing functions"
        case .predicateAsync:
            return "predicate is async — Gen<T>.filter is synchronous"
        case .predicateMultiArg:
            return "predicate takes multiple arguments — Gen<T>.filter is unary"
        case .predicateArgNotGeneratable:
            return "predicate's argument type isn't auto-generatable"
        case .predicateReturnNotEquatable:
            return "predicate's return type isn't Equatable — N-class equality classification needs ==(_:_:)"
        }
    }
}
