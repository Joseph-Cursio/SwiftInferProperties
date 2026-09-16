/// One function or function pair a template matched, as the renderer and every stub writer see it.
///
/// Split out of `Suggestion.swift` when that file passed SwiftLint's 400-line ceiling — the same
/// move `LiftedTestEmitter+Totality` and `InteractiveTriage+AcceptTotality` were made by. The seam
/// is a real one rather than a line-count convenience: `Suggestion` is what a template PRODUCES
/// and `Evidence` is what it MATCHED, and the two are consumed by different halves of the tool.
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

    /// True when this row is an instance method (has a containing type and
    /// is not `static`). Lets the verify emitter choose the
    /// `receiver.method(...)` call shape. Defaults `false` for the many
    /// non-`FunctionSummary` evidence sites (interaction/verify rows) that
    /// don't carry callee-shape metadata.
    public let isInstanceMethod: Bool

    /// True when the instance method is `mutating` / returns `Void`.
    public let isMutatingMethod: Bool

    /// True when the function takes no parameters.
    public let isNullary: Bool

    /// True when the return type is the carrier itself (`Self` or the
    /// containing type up to generic arguments).
    public let returnsSelfType: Bool

    /// True when this row is a read-only COMPUTED PROPERTY (recall epic #1).
    /// Lets the verify emitter emit a property access (`value.conjugate`) rather
    /// than a call (`value.conjugate()`).
    public let isComputedProperty: Bool

    /// Each parameter's type as written, in declaration order.
    ///
    /// Carried rather than recovered from `signature`. That string is a *rendering* — the types
    /// comma-joined — and splitting it back apart is wrong the moment a parameter is itself
    /// generic over two arguments (`Dictionary<String, Int>`) or a tuple. The list is what the
    /// scanner had; re-deriving it from prose it printed is the mistake `docs/parsing-catalog-gap`
    /// keeps finding elsewhere.
    ///
    /// Consumed by verify, which needs one generated value **per parameter** to state a law about
    /// an n-ary function. Measured 2026-08-03: 19 of 126 `predicate` entries failed to compile as
    /// `missing argument for parameter #2`, because the composer had only ever been given one
    /// type and so emitted one argument.
    ///
    /// Defaulted to `[]` so the many hand-built `Evidence` values in tests and non-scanner call
    /// sites keep compiling; an empty list means *not recorded*, and verify falls back to the
    /// single-carrier behaviour.
    public let parameterTypeNames: [String]

    /// Each parameter's **internal** name, in declaration order — the name the body uses, not the
    /// label a caller writes. `func wordCount(forScale scale: Int)` records `["scale"]`.
    ///
    /// Carried for the same reason as `parameterTypeNames`, and consumed by the one law whose text
    /// is written in the declaration's own scope. `guard-domain`'s condition is `scale > 0`, and a
    /// stub that evaluates it from outside has to know which names in that string are values it
    /// must supply. The **label** cannot answer: it is often absent (`_`) and often different from
    /// the internal name, so a rewrite keyed on labels binds the wrong thing or nothing.
    ///
    /// Defaulted to `[]` so the many hand-built `Evidence` values keep compiling; empty means
    /// *not recorded*, and the guard-domain writer declines rather than binding positionally
    /// against a list it does not have.
    public let parameterInternalNames: [String]

    /// The full lexical type path of the declaring type — `"SwiftInferCommand.Scaffold"`
    /// where the carrier records as `"Scaffold"`. Mirrors
    /// `FunctionSummary.qualifiedContainingTypeName`; see that doc for why the bare
    /// name is kept alongside. `nil` means *not recorded*, and verify falls back to
    /// the carrier name.
    public let qualifiedTypeName: String?

    /// The global actor isolating the subject — `"MainActor"` — or `nil`.
    ///
    /// An emitted test calling an isolated function from a nonisolated closure does not compile,
    /// and the diagnostic (`expression is 'async' but is not marked with 'await'`) names neither
    /// the actor nor the subject. Carried so the emitter can hop rather than the reader guess.
    /// `nil` means *not recorded*, which is the behaviour every call site had before this.
    public let globalActor: String?

    public init(
        displayName: String,
        signature: String,
        location: SourceLocation,
        isInstanceMethod: Bool = false,
        isMutatingMethod: Bool = false,
        isNullary: Bool = false,
        returnsSelfType: Bool = false,
        isComputedProperty: Bool = false,
        parameterTypeNames: [String] = [],
        parameterInternalNames: [String] = [],
        qualifiedTypeName: String? = nil,
        globalActor: String? = nil
    ) {
        self.displayName = displayName
        self.signature = signature
        self.location = location
        self.isInstanceMethod = isInstanceMethod
        self.isMutatingMethod = isMutatingMethod
        self.isNullary = isNullary
        self.returnsSelfType = returnsSelfType
        self.isComputedProperty = isComputedProperty
        self.parameterTypeNames = parameterTypeNames
        self.parameterInternalNames = parameterInternalNames
        self.qualifiedTypeName = qualifiedTypeName
        self.globalActor = globalActor
    }

    /// This row with its global actor filled in — used by the post-pass that resolves isolation
    /// inherited through a protocol, which the per-file scan cannot see.
    public func withGlobalActor(_ actor: String) -> Self {
        Self(
            displayName: displayName,
            signature: signature,
            location: location,
            isInstanceMethod: isInstanceMethod,
            isMutatingMethod: isMutatingMethod,
            isNullary: isNullary,
            returnsSelfType: returnsSelfType,
            isComputedProperty: isComputedProperty,
            parameterTypeNames: parameterTypeNames,
            parameterInternalNames: parameterInternalNames,
            qualifiedTypeName: qualifiedTypeName,
            globalActor: actor
        )
    }
}

/// Generator selection + sampling state for a suggestion. PRD §4.3 requires
/// every suggestion's evidence record to carry these three fields; M1 emits
/// placeholder values since selection + sampling are deferred.
public struct GeneratorMetadata: Sendable, Equatable {

    /// Where the generator came from. M1 always reports
    /// `.notYetComputed` — selection is gated on `DerivationStrategist`
    /// being publicly exposed from SwiftPropertyLaws (PRD §11, §21 OQ #4)
    /// and lands at M3.
    public enum Source: String, Sendable, Equatable {
        case derivedCaseIterable
        case derivedRawRepresentable
        case derivedMemberwise
        case derivedInitializer
        case derivedEnumCases
        case derivedCodableRoundTrip
        /// A stdlib / collection / composite carrier the corpus doesn't declare
        /// (`String`, `[String]`, `[String: Int]`, a composite of resolvable
        /// leaves) — derived directly via `CompositeMemberParser`, not by matching
        /// a corpus `TypeShape`. Fills the gap the app road-test surfaced: kernels
        /// are overwhelmingly stdlib/collection-typed, and those were being skipped
        /// to `.notYetComputed` despite being trivially generatable.
        case derivedComposite
        case registered
        case todo
        case inferredFromTests

        /// No `Gen` is synthesisable, but the carrier has a known construction
        /// path from another representation and a runnable recipe is attached —
        /// see `ProxyConstruction`. Distinct from `.notYetComputed` because the
        /// reader is not stuck: "not derived" and "cannot be tested" are
        /// different claims, and conflating them cost the road-test subject 60%
        /// of its suggestions.
        case proxyRecipe
        case notYetComputed
    }

    // The identically-named `Confidence` in `Tests/Fixtures/algebraic-survey-corpus/` is sample
    // input this tool *parses*, not a second production model — it's `Int`-raw-valued and mirrors
    // these case names by coincidence. Not real duplication.
    // swiftprojectlint:disable:next parallel-enum-shape
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
    public static let m1Placeholder = Self(
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
