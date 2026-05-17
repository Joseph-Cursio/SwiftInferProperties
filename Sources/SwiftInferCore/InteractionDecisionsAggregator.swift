import Foundation

/// V1.102 (cycle-99 calibration helper) — pure aggregation over
/// `InteractionDecisions`. Computes per-family + overall acceptance
/// rates suitable for the cycle-N findings doc table.
///
/// The acceptance rate, per the interaction-invariant triage rubric:
///
///     acceptance = (accepted + acceptedAsConformance)
///                / (accepted + acceptedAsConformance + rejected)
///
/// `skipped` is excluded from both numerator and denominator (matches
/// v1's "unknown" handling in `cycle-6-triage-rubric.md`).
///
/// Per-family tier-promotion gate (PRD §3.5 corollary): three
/// consecutive cycles at ≥ 70% promote a family from default-
/// `.possible` to `.likely`; three more at ≥ 70% promote to
/// `.strong`. The aggregator returns the rate; the cross-cycle
/// stability check lives in the findings doc.
public enum InteractionDecisionsAggregator {

    /// Per-family or overall counts + acceptance rate. Skipped
    /// records are tracked separately from the denominator so the
    /// findings doc can report skip rate as a rubric-quality signal.
    public struct Bucket: Equatable, Sendable {
        public let accepted: Int
        public let acceptedAsConformance: Int
        public let rejected: Int
        public let skipped: Int

        public init(
            accepted: Int = 0,
            acceptedAsConformance: Int = 0,
            rejected: Int = 0,
            skipped: Int = 0
        ) {
            self.accepted = accepted
            self.acceptedAsConformance = acceptedAsConformance
            self.rejected = rejected
            self.skipped = skipped
        }

        /// Total recorded decisions (includes skipped).
        public var total: Int {
            accepted + acceptedAsConformance + rejected + skipped
        }

        /// Records that count toward the acceptance-rate
        /// denominator. Excludes `skipped`.
        public var decided: Int {
            accepted + acceptedAsConformance + rejected
        }

        /// Acceptance numerator — both accept arms collapse here.
        public var acceptedTotal: Int {
            accepted + acceptedAsConformance
        }

        /// Acceptance rate in [0, 1]. `nil` when the family has no
        /// decided records (avoids 0/0 → false 0% reports).
        public var acceptanceRate: Double? {
            guard decided > 0 else { return nil }
            return Double(acceptedTotal) / Double(decided)
        }

        /// Skip rate in [0, 1]. `nil` when the family has no
        /// recorded decisions at all. Tracked separately so the
        /// findings doc can flag families above the rubric's 30%
        /// refinement threshold.
        public var skipRate: Double? {
            guard total > 0 else { return nil }
            return Double(skipped) / Double(total)
        }
    }

    /// Result of aggregating one `InteractionDecisions` (or a
    /// merge thereof) into per-family + overall buckets.
    public struct Report: Equatable, Sendable {
        public let perFamily: [InteractionInvariantFamily: Bucket]
        public let overall: Bucket

        public init(
            perFamily: [InteractionInvariantFamily: Bucket],
            overall: Bucket
        ) {
            self.perFamily = perFamily
            self.overall = overall
        }

        /// Lookup with `.zero` fallback. Keeps the renderer simple
        /// (every family row prints, even at zero decisions).
        public func bucket(for family: InteractionInvariantFamily) -> Bucket {
            perFamily[family] ?? Bucket()
        }
    }

    /// Aggregate `decisions` into per-family buckets.
    public static func aggregate(_ decisions: InteractionDecisions) -> Report {
        var perFamily: [InteractionInvariantFamily: Counts] = [:]
        var overall = Counts()
        for record in decisions.records {
            var existing = perFamily[record.family] ?? Counts()
            existing.count(record.decision)
            overall.count(record.decision)
            perFamily[record.family] = existing
        }
        let perFamilyBuckets = perFamily.mapValues { $0.bucket }
        return Report(perFamily: perFamilyBuckets, overall: overall.bucket)
    }

    /// Mutable counter used while folding records. Lives at module
    /// scope to keep the aggregator below SwiftLint's nesting cap and
    /// to keep `aggregate` readable.
    private struct Counts {
        var accepted = 0
        var asConformance = 0
        var rejected = 0
        var skipped = 0

        mutating func count(_ decision: InteractionDecision) {
            switch decision {
            case .accepted: accepted += 1
            case .acceptedAsConformance: asConformance += 1
            case .rejected: rejected += 1
            case .skipped: skipped += 1
            }
        }

        var bucket: Bucket {
            Bucket(
                accepted: accepted,
                acceptedAsConformance: asConformance,
                rejected: rejected,
                skipped: skipped
            )
        }
    }
}
