import Foundation
import SwiftInferCore
import Testing

@Suite("Decisions.merge — V1.4.1 multi-corpus aggregation")
struct DecisionsMergeTests {

    private static func record(
        identityHash: String,
        decision: Decision,
        timestamp: TimeInterval
    ) -> DecisionRecord {
        DecisionRecord(
            identityHash: identityHash,
            template: "round-trip",
            scoreAtDecision: 80,
            tier: .strong,
            decision: decision,
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
    }

    @Test("Disjoint decisions merge to the union")
    func disjointMerge() {
        let lhs = Decisions(records: [Self.record(identityHash: "AA", decision: .accepted, timestamp: 100)])
        let rhs = Decisions(records: [Self.record(identityHash: "BB", decision: .rejected, timestamp: 200)])
        let merged = lhs.merge(rhs)
        #expect(merged.records.count == 2)
        #expect(merged.records.contains { $0.identityHash == "AA" })
        #expect(merged.records.contains { $0.identityHash == "BB" })
    }

    @Test("Overlapping identity: later timestamp wins")
    func overlapLaterWins() throws {
        let lhs = Decisions(records: [Self.record(identityHash: "AA", decision: .skipped, timestamp: 100)])
        let rhs = Decisions(records: [Self.record(identityHash: "AA", decision: .accepted, timestamp: 200)])
        let merged = lhs.merge(rhs)
        #expect(merged.records.count == 1)
        let winner = try #require(merged.records.first)
        #expect(winner.decision == .accepted)
    }

    @Test("Overlapping identity: order-independent — older RHS does not displace newer LHS")
    func overlapOrderIndependent() throws {
        let lhs = Decisions(records: [Self.record(identityHash: "AA", decision: .accepted, timestamp: 200)])
        let rhs = Decisions(records: [Self.record(identityHash: "AA", decision: .skipped, timestamp: 100)])
        let merged = lhs.merge(rhs)
        #expect(merged.records.count == 1)
        let winner = try #require(merged.records.first)
        #expect(winner.decision == .accepted)
    }

    @Test("Schema version is the max of the two inputs")
    func schemaVersionMaxes() {
        let lhs = Decisions(schemaVersion: 1, records: [])
        let rhs = Decisions(schemaVersion: 2, records: [])
        let merged = lhs.merge(rhs)
        #expect(merged.schemaVersion == 2)
    }

    @Test("Empty merge with empty is empty")
    func emptyMergeEmpty() {
        let merged = Decisions.empty.merge(.empty)
        #expect(merged.records.isEmpty)
    }
}
