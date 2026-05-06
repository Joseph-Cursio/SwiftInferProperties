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

    public init(
        predicateName: String,
        argTypeName: String,
        returnTypeName: String,
        markerSetName: String,
        markers: [String],
        siteCountsByMarker: [String: Int],
        predicateVeto: PredicateVetoReason?,
        suggestedGeneratorsByMarker: [String: String]
    ) {
        self.predicateName = predicateName
        self.argTypeName = argTypeName
        self.returnTypeName = returnTypeName
        self.markerSetName = markerSetName
        self.markers = markers
        self.siteCountsByMarker = siteCountsByMarker
        self.predicateVeto = predicateVeto
        self.suggestedGeneratorsByMarker = suggestedGeneratorsByMarker
    }
}
