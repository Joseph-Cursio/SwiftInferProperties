/// A candidate property suggestion emitted by a template. The full record
/// the M1 CLI renders for human review per PRD §4.5.
public struct Suggestion: Sendable, Equatable {

    /// Template that produced this suggestion (e.g. `"idempotence"`,
    /// `"round-trip"`). Stored as a string so the registry is open to v1.1
    /// constraint-engine additions without a Core-side enum bottleneck.
    public var templateName: String

    /// Source-level evidence that motivated the suggestion. For unary
    /// templates this is one entry; cross-function templates (round-trip,
    /// landing M1.4) carry both halves of the pair.
    public var evidence: [Evidence]

    /// Score and accumulated signals.
    public var score: Score

    /// Generator selection + sampling state. M1 emits placeholder values
    /// (`.notYetComputed` / `.notRun`) since both are deferred per the M1
    /// Plan (M3 prerequisite for generator, M4 for sampling).
    public var generator: GeneratorMetadata

    /// Two-sided block per §4.5. Built by the template at suggest time
    /// from active signals + template-known caveats.
    public var explainability: ExplainabilityBlock

    /// Stable hash per §7.5 — the key under which decisions live in
    /// `.swiftinfer/decisions.json` (M-post) and the value the developer
    /// puts in a `// swiftinfer: skip <hash>` rejection marker.
    public var identity: SuggestionIdentity

    /// `nil` for TemplateEngine-originated suggestions; populated for
    /// TestLifter-originated suggestions promoted via
    /// `LiftedSuggestion.toSuggestion(...)` (TestLifter M3.0). Carries the
    /// originating test method name + source location so the M3.3
    /// accept-flow can name the writeout file + emit a provenance comment
    /// header. Opaque to TemplateEngine consumers.
    public var liftedOrigin: LiftedOrigin?

    /// `nil` unless `generator.source == .inferredFromTests` (TestLifter
    /// M4.3). Carries the synthesized argument-spec + observed-site
    /// count the M4.4 accept-flow renderer uses to emit a `Gen<T> {
    /// T(label: <Gen<...>>.run(), ...) }` stub body. Opaque to Core +
    /// TemplateEngine consumers — only the renderer reads it. The
    /// field mirrors the `liftedOrigin` placement decision: pure
    /// additive optional, defaults `nil`.
    public var mockGenerator: MockGenerator?

    /// **V1.34.A** — carrier type name for SemanticIndex `--type` query
    /// filtering (PRD §20.1 follow-up). Populated from the natural
    /// per-template source:
    ///   - Unary templates (Idempotence, Monotonicity,
    ///     InvariantPreservation, DualStyleConsistency): the originating
    ///     `FunctionSummary.containingTypeName`.
    ///   - Pair templates (RoundTrip, InversePair, Commutativity,
    ///     Associativity): the forward side's `containingTypeName`.
    ///   - IdentityElement: the operation's `containingTypeName`.
    ///   - Lifted templates (`+Lifted` variants, Composition): the
    ///     `LiftedTransformation.carrier` string.
    ///
    /// `nil` for free functions (top-level functions not nested in a
    /// type) and templates that don't expose a meaningful carrier.
    /// Backward-compatible: existing Suggestion construction sites
    /// that don't pass this argument receive the default-nil value.
    public var carrier: String?

    /// The generators this law needs, written out so the reader can run them — see `GeneratorRecipe`.
    ///
    /// Empty for the templates that have not declared any. A law whose counterexamples live in
    /// COLLISIONS passes vacuously under a uniform generator, so for those templates this is not a
    /// nicety: it is the half of the artefact that decides whether the law can fail at all.
    public var generatorRecipes: [GeneratorRecipe]

    /// **V1.149** — the *generator* carrier, distinct from `carrier`
    /// (which is the function's owner / call-site qualifier). For a method
    /// defined on the carrier the two coincide and this is `nil`. For a
    /// `static`/free function whose property flows through a parameter —
    /// e.g. `static func indent(_ s: String) -> String` on an unrelated
    /// `enum Engine` — `carrier` is `"Engine"` and `carrierTypeName` is
    /// `"String"` (the `T` the generated `Gen<T>` must produce). Threaded
    /// into `SemanticIndexEntry.carrierTypeName`; the verify path reads it
    /// (falling back to `carrier`) to derive the generator. Backward-
    /// compatible: defaults `nil`.
    public var carrierTypeName: String?

    /// **#477** — what the template actually matched, as data.
    ///
    /// `nil` for every template that carries no payload, which is most of them: a template whose
    /// law is recoverable from the signature and the callee needs nothing here. It is populated by
    /// the four whose match was computed and then **discarded into prose** — `guard-domain`,
    /// `selection-subset`, `diff-disjointness`, `partition` — so a stub writer reads fields instead
    /// of parsing a signal detail back apart. See `TemplateMatch` for why that parse must not be
    /// the fallback.
    ///
    /// Backward-compatible: defaults `nil`, and `withGenerator(_:)`'s copy-mutation rule means no
    /// rebuild site can silently drop it.
    public var match: TemplateMatch?

    public init(
        templateName: String,
        evidence: [Evidence],
        score: Score,
        generator: GeneratorMetadata,
        explainability: ExplainabilityBlock,
        identity: SuggestionIdentity,
        liftedOrigin: LiftedOrigin? = nil,
        mockGenerator: MockGenerator? = nil,
        carrier: String? = nil,
        carrierTypeName: String? = nil,
        generatorRecipes: [GeneratorRecipe] = [],
        match: TemplateMatch? = nil
    ) {
        self.templateName = templateName
        self.evidence = evidence
        self.score = score
        self.generator = generator
        self.explainability = explainability
        self.identity = identity
        self.liftedOrigin = liftedOrigin
        self.mockGenerator = mockGenerator
        self.carrier = carrier
        self.carrierTypeName = carrierTypeName
        self.generatorRecipes = generatorRecipes
        self.match = match
    }

    /// A copy with `explainability` replaced — used by the render-time stdlib
    /// anchor to append proven-analog / known-trap provenance lines without
    /// touching the score.
    ///
    /// **Mutate a copy; never rebuild field-by-field.** See `withGenerator(_:)`.
    public func withExplainability(_ block: ExplainabilityBlock) -> Self {
        var copy = self
        copy.explainability = block
        return copy
    }

    /// A copy with the generator metadata replaced — what `GeneratorSelection` produces.
    ///
    /// ## Why this exists, and why the field-by-field rebuild it replaces was a trap
    ///
    /// `Suggestion` was reconstructed argument-by-argument in four places. Every time a field was
    /// added, each of those four sites had to be updated by hand — and a site that forgot one did not
    /// fail to compile, because the omitted argument had a default. It produced a suggestion that
    /// rendered correctly in every visible respect **except** that one field was silently `nil` or
    /// empty.
    ///
    /// This is not hypothetical and it is not new. `GeneratorSelection` already carried a comment
    /// saying so:
    ///
    /// > *"the generator-carrier (`carrierTypeName`) must survive the generator-metadata rebuild;
    /// > omitting it silently reset it to nil, so the index/verify fell back to the owner type (this
    /// > dropped monotonicity's param-domain carrier set in V1.151)."*
    ///
    /// The lesson was written down and the trap was left armed. It caught the very next field:
    /// `generatorRecipes` — which is the half of a law that decides whether it can fail — vanished
    /// between the template and the renderer, and the partition law shipped with no generator.
    ///
    /// **Mutating a copy cannot drop a field.** A future field needs no edit here at all.
    public func withGenerator(_ metadata: GeneratorMetadata) -> Self {
        var copy = self
        copy.generator = metadata
        return copy
    }

    /// A copy with one more scoring signal folded in — what the verify-evidence post-pass produces.
    public func withAdditionalSignal(_ signal: Signal, explainability: ExplainabilityBlock) -> Self {
        var copy = self
        copy.score = Score(signals: score.signals + [signal])
        copy.explainability = explainability
        return copy
    }
}
