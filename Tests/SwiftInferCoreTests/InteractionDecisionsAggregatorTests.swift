import Foundation
@testable import SwiftInferCore
import Testing

// V1.102 (cycle-99 calibration helper) — InteractionDecisionsAggregator.
// Pure aggregation: no I/O.

@Suite("InteractionDecisionsAggregator — V1.102 per-family acceptance-rate math")
struct InteractionDecisionsAggregatorTests {

    private let now = ISO8601DateFormatter().date(from: "2026-05-17T12:00:00Z")!

    private func record(
        identity: String,
        family: InteractionInvariantFamily,
        decision: InteractionDecision,
        timestampOffset: TimeInterval = 0
    ) -> InteractionDecisionRecord {
        InteractionDecisionRecord(
            identityHash: identity,
            family: family,
            scoreAtDecision: 30,
            tier: .possible,
            reducerQualifiedName: "Test.body",
            decision: decision,
            timestamp: now.addingTimeInterval(timestampOffset)
        )
    }

    @Test func emptyDecisionsProduceAllZeroBuckets() {
        let report = InteractionDecisionsAggregator.aggregate(.empty)
        for family in InteractionInvariantFamily.allCases {
            #expect(report.bucket(for: family) == InteractionDecisionsAggregator.Bucket())
        }
        #expect(report.overall == InteractionDecisionsAggregator.Bucket())
        #expect(report.overall.acceptanceRate == nil)
        #expect(report.overall.skipRate == nil)
    }

    @Test func perFamilyBucketsCountAllFourDecisionArms() {
        let decisions = InteractionDecisions(records: [
            record(identity: "AAAA1", family: .cardinality, decision: .accepted),
            record(identity: "AAAA2", family: .cardinality, decision: .acceptedAsConformance),
            record(identity: "AAAA3", family: .cardinality, decision: .rejected),
            record(identity: "AAAA4", family: .cardinality, decision: .skipped),
            record(identity: "BBBB1", family: .idempotence, decision: .accepted),
            record(identity: "BBBB2", family: .idempotence, decision: .accepted)
        ])

        let report = InteractionDecisionsAggregator.aggregate(decisions)
        let card = report.bucket(for: .cardinality)
        #expect(card.accepted == 1)
        #expect(card.acceptedAsConformance == 1)
        #expect(card.rejected == 1)
        #expect(card.skipped == 1)
        #expect(card.total == 4)
        #expect(card.decided == 3)
        #expect(card.acceptedTotal == 2)

        let idem = report.bucket(for: .idempotence)
        #expect(idem.accepted == 2)
        #expect(idem.decided == 2)
    }

    @Test func acceptanceRateExcludesSkippedFromDenominator() {
        // 2 accepted + 0 conformance / (2 accepted + 0 conformance + 1 rejected) = 2/3
        let decisions = InteractionDecisions(records: [
            record(identity: "X1", family: .biconditional, decision: .accepted),
            record(identity: "X2", family: .biconditional, decision: .accepted),
            record(identity: "X3", family: .biconditional, decision: .rejected),
            record(identity: "X4", family: .biconditional, decision: .skipped),
            record(identity: "X5", family: .biconditional, decision: .skipped)
        ])
        let report = InteractionDecisionsAggregator.aggregate(decisions)
        let bucket = report.bucket(for: .biconditional)
        #expect(bucket.acceptanceRate != nil)
        if let rate = bucket.acceptanceRate {
            #expect(abs(rate - 2.0 / 3.0) < 1e-9)
        }
        #expect(bucket.skipRate != nil)
        if let skipRate = bucket.skipRate {
            #expect(abs(skipRate - 2.0 / 5.0) < 1e-9)
        }
    }

    @Test func bothAcceptArmsCollapseIntoAcceptanceNumerator() {
        // 1 accepted + 1 acceptedAsConformance / (2 + 0 rejected) = 100%
        let decisions = InteractionDecisions(records: [
            record(identity: "Y1", family: .conservation, decision: .accepted),
            record(identity: "Y2", family: .conservation, decision: .acceptedAsConformance)
        ])
        let report = InteractionDecisionsAggregator.aggregate(decisions)
        let bucket = report.bucket(for: .conservation)
        #expect(bucket.acceptedTotal == 2)
        #expect(bucket.acceptanceRate == 1.0)
    }

    @Test func familyWithNoDecisionsReturnsNilRate() {
        let decisions = InteractionDecisions(records: [
            record(identity: "Z1", family: .cardinality, decision: .accepted)
        ])
        let report = InteractionDecisionsAggregator.aggregate(decisions)
        // Family with no records — buckets default to zero, rate nil
        let refint = report.bucket(for: .referentialIntegrity)
        #expect(refint.acceptanceRate == nil)
        #expect(refint.skipRate == nil)
    }

    @Test func familyWithOnlySkippedReturnsNilAcceptanceRate() {
        // No decisions hit the denominator — rate should be nil, not 0%.
        let decisions = InteractionDecisions(records: [
            record(identity: "W1", family: .cardinality, decision: .skipped),
            record(identity: "W2", family: .cardinality, decision: .skipped)
        ])
        let report = InteractionDecisionsAggregator.aggregate(decisions)
        let card = report.bucket(for: .cardinality)
        #expect(card.acceptanceRate == nil)
        #expect(card.skipRate == 1.0)
    }

    @Test func overallBucketSumsAcrossAllFamilies() {
        let decisions = InteractionDecisions(records: [
            record(identity: "A", family: .cardinality, decision: .accepted),
            record(identity: "B", family: .idempotence, decision: .accepted),
            record(identity: "C", family: .biconditional, decision: .rejected),
            record(identity: "D", family: .conservation, decision: .skipped)
        ])
        let report = InteractionDecisionsAggregator.aggregate(decisions)
        #expect(report.overall.accepted == 2)
        #expect(report.overall.rejected == 1)
        #expect(report.overall.skipped == 1)
        #expect(report.overall.total == 4)
        // 2/3 acceptance rate (1 skipped excluded)
        if let rate = report.overall.acceptanceRate {
            #expect(abs(rate - 2.0 / 3.0) < 1e-9)
        }
    }

    @Test func mergeKeepsLatestDecisionPerIdentity() {
        // Two decisions for the same identity — later timestamp wins.
        let earlier = record(
            identity: "DUPE",
            family: .cardinality,
            decision: .rejected,
            timestampOffset: 0
        )
        let later = record(
            identity: "DUPE",
            family: .cardinality,
            decision: .accepted,
            timestampOffset: 3_600
        )
        let merged = InteractionDecisions(records: [earlier])
            .merge(InteractionDecisions(records: [later]))
        let report = InteractionDecisionsAggregator.aggregate(merged)
        let bucket = report.bucket(for: .cardinality)
        #expect(bucket.accepted == 1)
        #expect(bucket.rejected == 0)
    }
}
