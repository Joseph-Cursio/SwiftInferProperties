/// A candidate property suggestion emitted by a template. The full record
/// the M1 CLI renders for human review per PRD v0.3 §4.5.
public struct Suggestion: Sendable, Equatable {

    /// Template that produced this suggestion (e.g. `"idempotence"`,
    /// `"round-trip"`). Stored as a string so the registry is open to v1.1
    /// constraint-engine additions without a Core-side enum bottleneck.
    public let templateName: String

    /// Source-level evidence that motivated the suggestion. For unary
    /// templates this is one entry; cross-function templates (round-trip,
    /// landing M1.4) carry both halves of the pair.
    public let evidence: [Evidence]

    /// Score and accumulated signals.
    public let score: Score

    /// Generator selection + sampling state. M1 emits placeholder values
    /// (`.notYetComputed` / `.notRun`) since both are deferred per the M1
    /// Plan (M3 prerequisite for generator, M4 for sampling).
    public let generator: GeneratorMetadata

    /// Two-sided block per §4.5. Built by the template at suggest time
    /// from active signals + template-known caveats.
    public let explainability: ExplainabilityBlock

    /// Stable hash per §7.5 — the key under which decisions live in
    /// `.swiftinfer/decisions.json` (M-post) and the value the developer
    /// puts in a `// swiftinfer: skip <hash>` rejection marker.
    public let identity: SuggestionIdentity

    /// `nil` for TemplateEngine-originated suggestions; populated for
    /// TestLifter-originated suggestions promoted via
    /// `LiftedSuggestion.toSuggestion(...)` (TestLifter M3.0). Carries the
    /// originating test method name + source location so the M3.3
    /// accept-flow can name the writeout file + emit a provenance comment
    /// header. Opaque to TemplateEngine consumers.
    public let liftedOrigin: LiftedOrigin?

    /// `nil` unless `generator.source == .inferredFromTests` (TestLifter
    /// M4.3). Carries the synthesized argument-spec + observed-site
    /// count the M4.4 accept-flow renderer uses to emit a `Gen<T> {
    /// T(label: <Gen<...>>.run(), ...) }` stub body. Opaque to Core +
    /// TemplateEngine consumers — only the renderer reads it. The
    /// field mirrors the `liftedOrigin` placement decision: pure
    /// additive optional, defaults `nil`.
    public let mockGenerator: MockGenerator?

    public init(
        templateName: String,
        evidence: [Evidence],
        score: Score,
        generator: GeneratorMetadata,
        explainability: ExplainabilityBlock,
        identity: SuggestionIdentity,
        liftedOrigin: LiftedOrigin? = nil,
        mockGenerator: MockGenerator? = nil
    ) {
        self.templateName = templateName
        self.evidence = evidence
        self.score = score
        self.generator = generator
        self.explainability = explainability
        self.identity = identity
        self.liftedOrigin = liftedOrigin
        self.mockGenerator = mockGenerator
    }
}

/// Source-level evidence row — one function or function pair the template
/// matched against. Captured as text rather than a pointer back to the
/// `FunctionSummary` so renderer output is decoupled from the parsing
/// pipeline.
public struct Evidence: Sendable, Equatable {

    /// Human-facing function name with parameter labels, e.g.
    /// `"normalize(_:)"`.
    public let displayName: String

    /// Trimmed function signature, e.g. `"(String) -> String"`.
    public let signature: String

    /// File-relative location of the `func` keyword.
    public let location: SourceLocation

    public init(displayName: String, signature: String, location: SourceLocation) {
        self.displayName = displayName
        self.signature = signature
        self.location = location
    }
}

/// Generator selection + sampling state for a suggestion. PRD §4.3 requires
/// every suggestion's evidence record to carry these three fields; M1 emits
/// placeholder values since selection + sampling are deferred.
public struct GeneratorMetadata: Sendable, Equatable {

    /// Where the generator came from. M1 always reports
    /// `.notYetComputed` — selection is gated on `DerivationStrategist`
    /// being publicly exposed from SwiftProtocolLaws (PRD §11, §21 OQ #4)
    /// and lands at M3.
    public enum Source: String, Sendable, Equatable {
        case derivedCaseIterable
        case derivedRawRepresentable
        case derivedMemberwise
        case derivedCodableRoundTrip
        case registered
        case todo
        case inferredFromTests
        case notYetComputed
    }

    /// Confidence in the selected generator. `nil` until selection runs.
    public enum Confidence: String, Sendable, Equatable {
        case high
        case medium
        case low
    }

    /// Outcome of the sampling pass. M1 always reports `.notRun` — the
    /// seeded sampling policy lands at M4 per the M1 Plan.
    public enum SamplingResult: Sendable, Equatable {
        case passed(trials: Int)
        case failed(seed: UInt64, counterexample: String)
        case notRun
    }

    public let source: Source
    public let confidence: Confidence?
    public let sampling: SamplingResult

    public init(source: Source, confidence: Confidence?, sampling: SamplingResult) {
        self.source = source
        self.confidence = confidence
        self.sampling = sampling
    }

    /// Placeholder used by every M1 suggestion. Generator selection lands
    /// at M3 and sampling at M4 — until then both fields are explicit
    /// `notYetComputed` / `notRun` so the explainability block can render
    /// them honestly.
    public static let m1Placeholder = GeneratorMetadata(
        source: .notYetComputed,
        confidence: nil,
        sampling: .notRun
    )
}

/// Two-sided explainability block per §4.5. Renderer responsibility — the
/// template builds these arrays in order; the renderer formats them.
public struct ExplainabilityBlock: Sendable, Equatable {

    /// Lines that go under "Why suggested" — typically evidence rows
    /// followed by per-signal lines. Each line is rendered verbatim with
    /// a leading bullet glyph by `SuggestionRenderer`.
    public let whySuggested: [String]

    /// Lines that go under "Why this might be wrong" — active counter-
    /// signals + template-known caveats. May be empty for a Strong
    /// suggestion with no caveats; the renderer emits an explicit "no
    /// known caveats" line in that case so absence is visible.
    public let whyMightBeWrong: [String]

    public init(whySuggested: [String], whyMightBeWrong: [String]) {
        self.whySuggested = whySuggested
        self.whyMightBeWrong = whyMightBeWrong
    }
}
