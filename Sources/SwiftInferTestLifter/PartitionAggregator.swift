import SwiftInferCore
import SwiftSyntax

/// Per-`(predicateName, markerPair)` accumulator backing
/// `PartitionAggregator.bucketsByKey`. Records positive / negative
/// matched sites and a count of marker-bearing methods that failed the
/// polarity / predicate-shape checks (the "outlier" signal that the
/// M11.1 detector consumes via `PRD §3.5 conservative-bias` rule).
struct PartitionAccumulator {

    let markerPair: MarkerPair
    var positiveSites: [PartitionSite] = []
    var negativeSites: [PartitionSite] = []
    var outlierSiteCount: Int = 0
    /// M13.3 — `false` once any positive site is observed using a
    /// non-canonical assertion form (e.g. `XCTAssertTrue(!predicate(x))`,
    /// `#expect(predicate(x))`, `XCTAssert(predicate(x))`). The detector
    /// reads `allPositiveCanonical && allNegativeCanonical` to decide
    /// `EquivalenceClassHint.coversDomain`. Only `XCTAssertTrue(predicate(x))`
    /// (positive bucket) and `XCTAssertFalse(predicate(x))` (negative
    /// bucket) without `!` negation count as canonical, matching the M13
    /// plan §"What M13 ships" axis 4 syntactic-coverage rule.
    var allPositiveCanonical: Bool = true
    var allNegativeCanonical: Bool = true

    mutating func add(classification: Classification, methodName: String) {
        switch classification {
        case .matched(_, .positive):
            positiveSites.append(PartitionSite(methodName: methodName))
        case .matched(_, .negative):
            negativeSites.append(PartitionSite(methodName: methodName))
        case .outlier:
            outlierSiteCount += 1
        }
    }

    mutating func recordCanonical(polarity: Polarity, isCanonical: Bool) {
        guard !isCanonical else { return }
        switch polarity {
        case .positive: allPositiveCanonical = false
        case .negative: allNegativeCanonical = false
        }
    }
}

struct PartitionKey: Hashable {
    let predicateName: String
    let markerPair: MarkerPair
}

/// Per-`(predicateName, markerSetName)` accumulator backing the
/// N-class branch of `PartitionAggregator.nClassBucketsByKey`. Records
/// per-marker bucket sites + an outlier count consumed by the M13.2
/// `NClassEquivalenceClassDetector`.
struct NClassPartitionAccumulator {

    let markerSet: MarkerSet
    var bucketsByMarker: [String: [PartitionSite]] = [:]
    var outlierSiteCount: Int = 0

    mutating func add(classification: NClassClassification, methodName: String) {
        switch classification {
        case .matched(_, let marker):
            bucketsByMarker[marker, default: []].append(PartitionSite(methodName: methodName))
        case .outlier:
            outlierSiteCount += 1
        }
    }
}

struct NClassPartitionKey: Hashable {
    let predicateName: String
    let markerSetName: String
}

/// Streaming aggregator the M11.2 `TestLifter.discover(in:)` loop drives
/// per-method so it doesn't have to retain `[SlicedTestBody]` for the
/// full discover run. Each call to `observe(method:slice:markerTable:)`
/// classifies the method against every marker pair, routes the result
/// into the per-`(predicateName, markerPair)` accumulator, and discards
/// the slice when the call returns. `finalize()` produces the final
/// `[PartitionCandidate]` array sorted by predicate name.
///
/// **M13.1 ranking:** when the same predicate fires under multiple
/// marker pairs, `finalize()` dedups to a single winning candidate per
/// predicate (highest combined site count; alphabetical tie-break by
/// `markerPair.positive`). Per M11 open-decision #8.
///
/// Restructured from the eager `extract(methods:slices:markerTable:)`
/// shape after the §13 row 4 memory test caught a 65MB regression — the
/// eager shape required the discover loop to accumulate `[SlicedTestBody]`
/// across all 500 corpus files, which transitively retained the SwiftSyntax
/// tree references that the original (per-iteration-discarded) detector
/// passes had been deallocating. Streaming aggregation reverts the
/// allocation profile to the pre-M11 baseline.
struct PartitionAggregator {

    private var bucketsByKey: [PartitionKey: PartitionAccumulator] = [:]
    private var nClassBucketsByKey: [NClassPartitionKey: NClassPartitionAccumulator] = [:]

    mutating func observe(
        method: TestMethodSummary,
        slice: SlicedTestBody,
        markerTable: [MarkerPair]
    ) {
        for pair in markerTable {
            guard let classification = EquivalenceClassMarkerExtractor.classify(
                method: method, slice: slice, markerPair: pair
            ) else {
                continue
            }
            guard let predicateName = classification.routingPredicateName else {
                break
            }
            let key = PartitionKey(predicateName: predicateName, markerPair: pair)
            bucketsByKey[key, default: PartitionAccumulator(markerPair: pair)]
                .add(classification: classification, methodName: method.methodName)
            // M13.3 — track canonical-form per matched site so the M11.1
            // detector can set `coversDomain` when both buckets exclusively
            // use `XCTAssertTrue(predicate(x))` / `XCTAssertFalse(predicate(x))`
            // without `!` negation.
            if case .matched(_, let polarity) = classification {
                let canonical = EquivalenceClassMarkerExtractor.isCanonicalCoversDomainForm(
                    assertion: slice.assertion, polarity: polarity
                )
                bucketsByKey[key]?.recordCanonical(polarity: polarity, isCanonical: canonical)
            }
            break
        }
    }

    /// M13.2 N-class observe pass — runs in parallel with the two-class
    /// `observe(method:slice:markerTable:)` for the same method. Different
    /// marker sets keep separate bucket accumulators; the M13.2 detector
    /// consumes one N-class candidate per `(predicate, markerSet)`.
    mutating func observeNClass(
        method: TestMethodSummary,
        slice: SlicedTestBody,
        markerSets: [MarkerSet]
    ) {
        for markerSet in markerSets {
            guard let classification = EquivalenceClassMarkerExtractor.classifyNClass(
                method: method, slice: slice, markerSet: markerSet
            ) else {
                continue
            }
            guard let predicateName = classification.routingPredicateName else {
                break
            }
            let key = NClassPartitionKey(
                predicateName: predicateName,
                markerSetName: markerSet.name
            )
            nClassBucketsByKey[key, default: NClassPartitionAccumulator(markerSet: markerSet)]
                .add(classification: classification, methodName: method.methodName)
            break
        }
    }

    /// Per-predicate ranking dedup (M11 open-decision #8 / M13.1
    /// acceptance): when the same predicate fires under multiple marker
    /// pairs, emit ONE candidate — the one with the highest combined
    /// site count (positive + negative). Tie-broken alphabetically by
    /// `markerPair.positive` so curated-default `Allowed` < `Pass` <
    /// `Success` < `Valid` ordering is deterministic across runs.
    /// Output sorted by `predicateName` for byte-stable downstream
    /// suggestion ordering (PRD §16 reproducibility).
    ///
    /// **M13.2 union:** the two-class candidates from `bucketsByKey` are
    /// concatenated with the N-class candidates from `nClassBucketsByKey`.
    /// Per M13 plan OD #8 a predicate firing under both a two-class pair
    /// AND an N-class set emits two candidates (different artifacts).
    /// Sort order: predicateName ascending; same-predicate two-class
    /// candidates sort before N-class; N-class ties broken by markerSet
    /// name.
    func finalize() -> [PartitionCandidate] {
        let twoClass = finalizeTwoClass()
        let nClass = finalizeNClass()
        return (twoClass + nClass).sorted(by: PartitionAggregator.sortCandidates)
    }

    private func finalizeTwoClass() -> [PartitionCandidate] {
        var winnerByPredicate: [String: RankedCandidate] = [:]
        for (key, accumulator) in bucketsByKey {
            let coversDomainSyntactic = accumulator.allPositiveCanonical
                && accumulator.allNegativeCanonical
                && !accumulator.positiveSites.isEmpty
                && !accumulator.negativeSites.isEmpty
            let candidate = PartitionCandidate(
                predicateName: key.predicateName,
                markerPair: accumulator.markerPair,
                markerSet: nil,
                positiveSites: accumulator.positiveSites,
                negativeSites: accumulator.negativeSites,
                outlierSiteCount: accumulator.outlierSiteCount,
                coversDomainSyntactic: coversDomainSyntactic
            )
            let ranked = RankedCandidate(candidate: candidate, accumulator: accumulator)
            if let existing = winnerByPredicate[key.predicateName] {
                if ranked.beats(existing) {
                    winnerByPredicate[key.predicateName] = ranked
                }
            } else {
                winnerByPredicate[key.predicateName] = ranked
            }
        }
        return winnerByPredicate.values.map(\.candidate)
    }

    private func finalizeNClass() -> [PartitionCandidate] {
        nClassBucketsByKey.map { key, accumulator in
            PartitionCandidate(
                predicateName: key.predicateName,
                markerPair: nil,
                markerSet: accumulator.markerSet,
                positiveSites: [],
                negativeSites: [],
                nClassBucketsByMarker: accumulator.bucketsByMarker,
                outlierSiteCount: accumulator.outlierSiteCount
            )
        }
    }

    private static func sortCandidates(_ lhs: PartitionCandidate, _ rhs: PartitionCandidate) -> Bool {
        if lhs.predicateName != rhs.predicateName {
            return lhs.predicateName < rhs.predicateName
        }
        let lhsIsTwoClass = lhs.markerPair != nil
        let rhsIsTwoClass = rhs.markerPair != nil
        if lhsIsTwoClass != rhsIsTwoClass {
            return lhsIsTwoClass
        }
        return (lhs.markerSet?.name ?? "") < (rhs.markerSet?.name ?? "")
    }
}

/// Per-predicate ranking helper used by `PartitionAggregator.finalize()`.
/// Carries the candidate plus the two scalar fields the rank comparison
/// needs — extracted into a struct so the dedup map's value isn't a
/// 3-tuple (SwiftLint `large_tuple` cap).
private struct RankedCandidate {

    let candidate: PartitionCandidate
    let totalSites: Int
    let positiveMarker: String

    init(candidate: PartitionCandidate, accumulator: PartitionAccumulator) {
        self.candidate = candidate
        self.totalSites = accumulator.positiveSites.count + accumulator.negativeSites.count
        self.positiveMarker = accumulator.markerPair.positive
    }

    func beats(_ other: RankedCandidate) -> Bool {
        if totalSites != other.totalSites {
            return totalSites > other.totalSites
        }
        return positiveMarker < other.positiveMarker
    }
}
