/// TestLifter M10.0 — inferred-domain hint attached to a `MockGenerator`
/// when the test corpus shows a reverse-side function's argument is
/// uniformly the forward-side function's output. Surfaces the pattern
/// the `DomainInferrer` (M10.2) detects across `[DomainCallSite]` rows
/// extracted from the test corpus's reverse-side call sites: "every
/// `decode(...)` site's argument was an `encode(...)` call expression
/// across N test sites" → narrow the round-trip generator from
/// `Gen<String>.string()` to `Gen<MyType>.map(encode)`.
///
/// **Advisory only.** PRD §3.5 conservative bias — hints don't change
/// the suggestion's score or tier; they render as `// Inferred domain:`
/// provenance comment lines in the accept-flow stub (M10.3) and, when
/// not vetoed, substitute the generator expression for `Gen<T>.map(...)`.
/// The user inspects + decides whether to apply.
public struct DomainHint: Sendable, Equatable {

    /// The forward-side function name from the M5 round-trip pair.
    /// Surfaced in the rendered comment and in the substituted generator
    /// expression (`Gen<T>.map(forward)`).
    public let forwardName: String

    /// The reverse-side function name from the M5 round-trip pair.
    /// Surfaced in the rendered comment ("reverse's argument was always
    /// forward's output").
    public let reverseName: String

    /// The producer function whose output the reverse-side argument was
    /// always observed to be. Equal to `forwardName` in M10's narrowed
    /// scope (round-trip pairs only); reserved as a distinct field per
    /// M10 plan OD #5 so the future v1.1+ Option A expansion (general
    /// consumer-producer chain detection) can populate it for non-round-
    /// trip pairs without a model migration.
    public let producerName: String

    /// The type name `T` that the override generator is `Gen<T>.map(producer)`.
    /// Pre-computed by the inferrer so the renderer doesn't re-derive it
    /// from the round-trip pair.
    public let domainTypeName: String

    /// Number of reverse-side call sites where the homogeneous producer
    /// pattern was observed. Mirrors `MockGenerator.siteCount` but per-
    /// hint so the rendered comment can say "across N sites" with the
    /// exact count that contributed to this hint. Always `≥ 3` per the
    /// M10 plan's threshold (mirrors M4.3 / M9).
    public let siteCount: Int

    /// Producer-veto reason when the M10.2 inferrer flagged the producer
    /// as ineligible for the `Gen<T>.map(producer)` override (per the M10
    /// plan's hard-veto policy, OD #2/#3/#4). `nil` when no veto fired
    /// (override applies). Surfaced in the rendered comment when non-nil
    /// so the user sees why narrowing was skipped.
    public let producerVeto: ProducerVetoReason?

    /// Recommended Swift expression. When `producerVeto == nil`, this is
    /// the substituted generator expression the M10.3 renderer emits in
    /// place of the original; when `producerVeto != nil`, the renderer
    /// surfaces this in the advisory comment text but doesn't substitute
    /// the generator. Pre-computed by the inferrer.
    public let suggestedGenerator: String

    /// TestLifter M16.0 — discriminator for which detector emitted this
    /// hint. M10's `DomainInferrer` emits with `.roundTripPair` (the
    /// default for back-compat); M16's `ConsumerProducerChainDetector`
    /// emits with `.consumerProducerChain`. Renderer + accept-flow
    /// dispatch on this field rather than re-parsing the (forward,
    /// reverse, producer) name triple to tell the two surfaces apart.
    public let origin: HintOrigin

    public init(
        forwardName: String,
        reverseName: String,
        producerName: String,
        domainTypeName: String,
        siteCount: Int,
        producerVeto: ProducerVetoReason?,
        suggestedGenerator: String,
        origin: HintOrigin = .roundTripPair
    ) {
        self.forwardName = forwardName
        self.reverseName = reverseName
        self.producerName = producerName
        self.domainTypeName = domainTypeName
        self.siteCount = siteCount
        self.producerVeto = producerVeto
        self.suggestedGenerator = suggestedGenerator
        self.origin = origin
    }
}

/// TestLifter M16.0 — provenance discriminator on `DomainHint` so the
/// renderer + accept-flow can distinguish M10's round-trip-pair surface
/// from M16's general consumer-producer chain surface without re-
/// parsing the hint's `(forwardName, reverseName, producerName)` triple.
///
/// Default is `.roundTripPair` — every M10 call site stays correct
/// without modification (M16 plan §"M16 ships" item 1; back-compat
/// invariant per item 6).
public enum HintOrigin: Sendable, Equatable {

    /// M10's `DomainInferrer` surface — the hint was emitted because a
    /// known M5 round-trip pair `(forward, reverse)` had every reverse-
    /// side test site receiving `forward(...)` output. Generator
    /// override (`Gen<T>.map(forward)`) applies when not vetoed.
    case roundTripPair

    /// TestLifter M16's `ConsumerProducerChainDetector` surface — the
    /// hint was emitted because some consumer in the corpus had every
    /// observed call-site argument being the same producer's output,
    /// outside the M5 round-trip-pair set. Comment-only advisory; no
    /// generator override (M10 owns that surface end-to-end per the
    /// M16 plan's "M16 explicitly defers" §).
    case consumerProducerChain
}

/// Reasons the M10.2 inferrer can mark a domain hint's producer as
/// ineligible for the `Gen<T>.map(producer)` generator override. Per
/// M10 plan OD #2/#3/#4, hitting any of these surfaces the hint as a
/// comment-only advisory (no generator substitution) — the
/// `swift-property-based` runner cannot shrink through `try!` / `await`,
/// `Gen<_>.map(_:)` is unary, and a non-generatable producer-arg type
/// has no path to a `Gen<T>` source.
public enum ProducerVetoReason: Sendable, Equatable {

    /// Producer is `throws`. Substituting `Gen<T>.map(throwingProducer)`
    /// would emit code that can't compile (or can't shrink) under the
    /// `swift-property-based` runner.
    case producerThrows

    /// Producer is `async`. `Gen<T>.map(_:)` is a synchronous
    /// transformation; substituting an async producer breaks the runner.
    case producerAsync

    /// Producer takes more than one argument. `Gen<T>.map(_:)` is unary;
    /// partial-application is fragile (the corpus may show variation in
    /// the second argument that the user expects to remain configurable).
    /// Defer to the future v1.1+ Option A expansion if real corpora show
    /// value in this case.
    case producerMultiArg

    /// Producer's single argument type is not auto-generatable per the
    /// M3+ `DerivationStrategist` strategy table (the strategist returns
    /// `.todo` or `.userGen`). The user can resolve `.userGen` cases by
    /// providing `static func gen()` themselves and re-running discover;
    /// the hint will then re-fire without the veto.
    case producerArgNotGeneratable

    /// TestLifter M16.2 — user-facing reason text surfaced in the
    /// consumer-producer chain explainability block + the M16.3 accept-
    /// flow comment-only writeout. Mirrors `PredicateVetoReason.advisoryReason`'s
    /// shape.
    public var advisoryReason: String {
        switch self {
        case .producerThrows:
            return "producer throws — Gen<T>.map cannot apply throwing functions"
        case .producerAsync:
            return "producer is async — Gen<T>.map is synchronous"
        case .producerMultiArg:
            return "producer takes multiple arguments — Gen<T>.map is unary"
        case .producerArgNotGeneratable:
            return "producer's argument type isn't auto-generatable"
        }
    }
}
