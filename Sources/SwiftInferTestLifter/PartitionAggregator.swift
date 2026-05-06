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
}

struct PartitionKey: Hashable {
    let predicateName: String
    let markerPair: MarkerPair
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
    func finalize() -> [PartitionCandidate] {
        var winnerByPredicate: [String: RankedCandidate] = [:]
        for (key, accumulator) in bucketsByKey {
            let candidate = PartitionCandidate(
                predicateName: key.predicateName,
                markerPair: accumulator.markerPair,
                markerSet: nil,
                positiveSites: accumulator.positiveSites,
                negativeSites: accumulator.negativeSites,
                outlierSiteCount: accumulator.outlierSiteCount
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
        return winnerByPredicate.values
            .map(\.candidate)
            .sorted { lhs, rhs in
                lhs.predicateName < rhs.predicateName
            }
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
