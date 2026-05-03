/// TestLifter M9.0 — inferred-precondition hint attached to a
/// `MockGenerator` argument position. Surfaces patterns the
/// `PreconditionInferrer` (M9.1) detects in `ConstructionRecord.
/// observedLiterals` rows: "all observed values for this position
/// are positive Ints across N test sites" → suggest
/// `Gen.int(in: 1...)` instead of the unconstrained generator.
///
/// **Advisory only.** PRD §3.5 conservative bias — hints don't
/// change the suggestion's score or tier; they render as
/// `// Inferred precondition:` provenance comment lines in the
/// accept-flow stub (M9.2). The user inspects + decides whether
/// to apply.
public struct PreconditionHint: Sendable, Equatable {

    /// Argument-shape index the hint applies to. Matches the
    /// position in `MockGenerator.argumentSpec`.
    public let position: Int

    /// Argument label as observed in the construction sites.
    /// `nil` for positional / unlabeled arguments. Surfaced in
    /// the rendered comment so the user knows which field the
    /// hint targets.
    public let argumentLabel: String?

    /// The pattern detected. See `PreconditionPattern` for the
    /// curated set.
    public let pattern: PreconditionPattern

    /// Number of test-site constructions where the pattern was
    /// observed. Mirrors `MockGenerator.siteCount` but per-hint
    /// so the rendered comment can say "across N test sites" with
    /// the exact count that contributed to this hint.
    public let siteCount: Int

    /// Recommended Swift expression the user could substitute into
    /// the generator. Pre-computed by the inferrer so the renderer
    /// doesn't have to re-derive it per pattern.
    public let suggestedGenerator: String

    public init(
        position: Int,
        argumentLabel: String?,
        pattern: PreconditionPattern,
        siteCount: Int,
        suggestedGenerator: String
    ) {
        self.position = position
        self.argumentLabel = argumentLabel
        self.pattern = pattern
        self.siteCount = siteCount
        self.suggestedGenerator = suggestedGenerator
    }
}

/// The curated set of precondition patterns `PreconditionInferrer`
/// (M9.1) recognizes. Per M9 plan OD #1, numerical patterns are
/// `Int`-only for v1.0 (`Float`/`Double` deferred — precision-class
/// concerns). Per OD #4, when multiple patterns match the same
/// observation, the most-specific case is emitted.
public enum PreconditionPattern: Sendable, Equatable {

    /// Every observed Int literal is `> 0`. Suggested generator:
    /// `Gen.int(in: 1...)`.
    case positiveInt

    /// Every observed Int literal is `>= 0`. Suggested generator:
    /// `Gen.int(in: 0...)`.
    case nonNegativeInt

    /// Every observed Int literal is `< 0`. Suggested generator:
    /// `Gen.int(in: ...(-1))`.
    case negativeInt

    /// Every observed Int literal falls within `[low, high]` where
    /// the range is narrower than the type's natural range and at
    /// least 2 distinct values were observed. Suggested generator:
    /// `Gen.int(in: low...high)`. Most-specific pattern; preempts
    /// `positiveInt` / `nonNegativeInt` when both apply.
    case intRange(low: Int, high: Int)

    /// Every observed string literal has non-zero length. Suggested
    /// generator caveat: "verify empty-string case". M9.2 surfaces
    /// this as a hint comment, not a generator change.
    case nonEmptyString

    /// Every observed string literal has length in `[low, high]`,
    /// with at least 2 distinct lengths observed (per OD #3 — single-
    /// length cases are filtered as trivial). Suggested generator:
    /// `Gen.string(of: low...high)`.
    case stringLength(low: Int, high: Int)

    /// Every observed Bool literal is the same value. Suggested
    /// hint: "observed only `<value>` across N sites — opposite case
    /// may be untested" (M9 plan OD #2 — emit advisory hint, no
    /// generator change).
    case constantBool(value: Bool)
}
