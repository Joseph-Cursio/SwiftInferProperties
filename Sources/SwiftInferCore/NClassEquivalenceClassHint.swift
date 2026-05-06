/// TestLifter M13.2 — N-class predicate-equivalence-class hint surfaced
/// by the M13.2 `NClassEquivalenceClassDetector` when a test corpus
/// partitions on a `MarkerSet` of cardinality ≥ 3 (per M13 plan §"What
/// M13 ships" axis 2). Peer to M11's two-class `EquivalenceClassHint`;
/// `EquivalenceClassHintKind` (M13.3) carries either across the
/// `InteractiveTriage.Context` side-map.
///
/// **Advisory only.** Same posture as M11's `EquivalenceClassHint`
/// (PRD §3.5 conservative bias) — the comment-only accept-flow writeout
/// names the suggested per-bucket `Gen<T>.gen().filter { p($0) == .case }`
/// generators; the user authors per-bucket properties manually.
///
/// Accept-flow filename per M13 plan OD #6: `EquivalenceClasses_<predicate>_<markerSetName>.swift`
/// — the marker-set name suffix disambiguates when the same predicate
/// fires under multiple marker sets.
public struct NClassEquivalenceClassHint: Sendable, Equatable, Codable {

    /// The predicate function name common to every site in every bucket.
    public let predicateName: String

    /// The type name `T` of the predicate's single argument (the type
    /// the per-bucket generators are over). Pre-computed by the
    /// detector; falls back to `"T"` when the predicate's
    /// `FunctionSummary` is unavailable.
    public let argTypeName: String

    /// The predicate's return type identifier (the enum / Equatable
    /// type the bucket cases live in). Surfaced for the rendered
    /// comment block ("the predicate `size: T -> Size` partitions ...").
    public let returnTypeName: String

    /// Name of the `MarkerSet` that fired this partition (e.g.
    /// `"Sizes"`). Used as the accept-flow file-name suffix per M13
    /// plan OD #6.
    public let markerSetName: String

    /// The marker names from the `MarkerSet` that successfully reached
    /// the per-bucket threshold, ordered as the marker set declares
    /// them. May be a prefix / subset of the original
    /// `MarkerSet.markers` if not every marker reached threshold (the
    /// detector would normally kill the candidate in that case; here
    /// we always carry all `≥ 3`-bucket markers in their original
    /// order).
    public let markers: [String]

    /// Per-bucket site count. Each entry's value is `≥ 3` per the
    /// M13.2 detector's per-bucket threshold. Keyed by the marker name
    /// from `markers` (verbatim, not lowercased).
    public let siteCountsByMarker: [String: Int]

    /// Predicate-shape veto reason when the M13.2 detector flagged the
    /// predicate as ineligible for the per-bucket
    /// `Gen<T>.gen().filter { p($0) == .case }` generator suggestion.
    /// Same posture as M11's `EquivalenceClassHint.predicateVeto` — the
    /// hint still emits with comment-only fallback; only the rendered
    /// generator suggestions are suppressed.
    public let predicateVeto: PredicateVetoReason?

    /// Per-bucket suggested Swift generator expression. When
    /// `predicateVeto == nil`, each value is the
    /// `Gen<T>.gen().filter { predicate($0) == .case }` form; when
    /// `predicateVeto != nil`, the renderer surfaces the veto reason
    /// in the documentation block and omits the generator suggestion.
    public let suggestedGeneratorsByMarker: [String: String]

    /// TestLifter M13.3 — `true` when the partition syntactically
    /// covers the domain `T` (markers cover every case of the
    /// predicate's enum return type, when that enum is declared in
    /// the same target). Surfaced in the rendered comment block as
    /// the additional exhaustiveness property:
    /// `forAll x: T. p(x) == .case₁ ∨ p(x) == .case₂ ∨ … ∨ p(x) == .caseₙ`.
    /// Defaults to `false`.
    public let coversDomain: Bool

    public init(
        predicateName: String,
        argTypeName: String,
        returnTypeName: String,
        markerSetName: String,
        markers: [String],
        siteCountsByMarker: [String: Int],
        predicateVeto: PredicateVetoReason?,
        suggestedGeneratorsByMarker: [String: String],
        coversDomain: Bool = false
    ) {
        self.predicateName = predicateName
        self.argTypeName = argTypeName
        self.returnTypeName = returnTypeName
        self.markerSetName = markerSetName
        self.markers = markers
        self.siteCountsByMarker = siteCountsByMarker
        self.predicateVeto = predicateVeto
        self.suggestedGeneratorsByMarker = suggestedGeneratorsByMarker
        self.coversDomain = coversDomain
    }
}

/// TestLifter M13.3 — sum-type carrier for the per-suggestion-identity
/// equivalence-class hint side-map. M11 two-class hints and M13.2
/// N-class hints flow through the same `InteractiveTriage.Context`
/// side-map shape, dispatching at the renderer + accept-flow level.
/// Codable so the side-map persists alongside the §13 row 4 memory
/// budget posture (the union case picks up a small fixed overhead per
/// entry; per-entry payload size is unchanged).
public enum EquivalenceClassHintKind: Sendable, Equatable, Codable {
    case twoClass(EquivalenceClassHint)
    case nClass(NClassEquivalenceClassHint)

    /// The predicate name common to both kinds — surfaced in the
    /// renderer header + accept-flow file naming.
    public var predicateName: String {
        switch self {
        case .twoClass(let hint): return hint.predicateName
        case .nClass(let hint): return hint.predicateName
        }
    }

    /// `true` when the hint's `coversDomain` flag is set; the renderer
    /// uses this to emit the exhaustiveness comment block.
    public var coversDomain: Bool {
        switch self {
        case .twoClass(let hint): return hint.coversDomain
        case .nClass(let hint): return hint.coversDomain
        }
    }
}
