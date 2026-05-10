/// V1.22.D — curated set of first-parameter labels that signal stride-
/// style range-bounded sequence iteration. Cycle-14 demotion target
/// (cycle-14 priority #1 → demoted to v1.18 → not shipped → cycle-18
/// priority #6 → shipped here in v1.22). Closes the lone Algo
/// `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` triple
/// (round-trip + inverse-pair + idempotence — though idempotence is
/// out-of-scope per v1.22 plan §"Workstream D" open decision #4).
///
/// **Why these labels:** they signal "advance OR retreat through a
/// range from one bound to another" — paired functions using these
/// labels are sequence-iteration bookends, not a round-trip codec
/// or a functional-inverse pair. The cycle-14 / cycle-17 measurements
/// found these picks at ACCEPT verdicts (correctness-positive), but
/// the suppression target is **emission usability** (auto-emitted
/// property tests need chunk-boundary generators which don't fit
/// standard `Gen<Int>` template); cycle-18's accumulated UX signal is
/// sufficient to demote them out of Strong-tier visibility.
///
/// Distinct from `DirectionLabels.curated` (V1.10.1 / V1.13.1):
/// direction labels are **cursor-incremental** (`after:` / `before:` /
/// `next:`); stride-style labels are **range-bounded** (`startingAt:` /
/// `endingAt:`). Both signal sequence-iteration semantics but at
/// different granularities — direction is "step by 1", stride is "go
/// from X to Y."
public enum StrideStyleLabels {

    /// Curated stride-style labels:
    ///
    /// - `startingAt` / `endingAt` — range-bounded (Algo `endOfChunk`
    ///   pair pattern; the v1.22 closure target).
    /// - `fromIndex` / `toIndex` — index-range bookends (common in
    ///   stdlib SubSequence APIs).
    /// - `startingFrom` — alternative start-bound naming.
    /// - `from` / `to` — minimal-form range bookends (the most common
    ///   in stdlib + stdlib-shaped user code).
    public static let curated: Set<String> = [
        "startingAt",
        "endingAt",
        "fromIndex",
        "toIndex",
        "startingFrom",
        "from",
        "to"
    ]
}
