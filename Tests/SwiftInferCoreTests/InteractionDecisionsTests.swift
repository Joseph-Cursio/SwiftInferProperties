import Foundation
import Testing
@testable import SwiftInferCore

// V2.0 accept-check follow-up — InteractionDecisions data model.
// Pure: no I/O.

@Suite("InteractionDecisions — V2.0 accept-flow data model")
struct InteractionDecisionsTests {

    private let now = ISO8601DateFormatter().date(from: "2026-05-15T12:00:00Z")!
    private let later = ISO8601DateFormatter().date(from: "2026-05-15T13:00:00Z")!

    private func record(
        identity: String = "DEADBEEFCAFEFACE",
        family: InteractionInvariantFamily = .cardinality,
        decision: InteractionDecision = .accepted,
        timestamp: Date? = nil
    ) -> InteractionDecisionRecord {
        InteractionDecisionRecord(
            identityHash: identity,
            family: family,
            scoreAtDecision: 80,
            tier: .strong,
            reducerQualifiedName: "Inbox.body",
            decision: decision,
            timestamp: timestamp ?? now
        )
    }

    // MARK: - InteractionDecision rawValues

    @Test("InteractionDecision rawValues are byte-stable across schema versions")
    func decisionRawValues() {
        #expect(InteractionDecision.accepted.rawValue == "accepted")
        #expect(InteractionDecision.acceptedAsConformance.rawValue == "accepted-as-conformance")
        #expect(InteractionDecision.rejected.rawValue == "rejected")
        #expect(InteractionDecision.skipped.rawValue == "skipped")
        #expect(InteractionDecision.allCases.count == 4)
    }

    // MARK: - Record lookup

    @Test("record(for:) finds a recorded decision by identity hash")
    func recordLookupByHash() {
        let target = record()
        let decisions = InteractionDecisions(records: [target])
        #expect(decisions.record(for: target.identityHash) == target)
        #expect(decisions.record(for: "00000000DEADBEEF") == nil)
    }

    // MARK: - Upsert semantics

    @Test("upserting a record with a known identity replaces the prior one")
    func upsertReplaces() {
        let original = record(decision: .accepted)
        let revised = record(decision: .rejected, timestamp: later)
        let decisions = InteractionDecisions(records: [original]).upserting(revised)
        #expect(decisions.records.count == 1)
        #expect(decisions.records[0].decision == .rejected)
        #expect(decisions.records[0].timestamp == later)
    }

    @Test("upserting a new identity appends at the end")
    func upsertAppendsNew() {
        let first = record(identity: "AAAAAAAAAAAAAAAA")
        let second = record(identity: "BBBBBBBBBBBBBBBB")
        let decisions = InteractionDecisions(records: [first]).upserting(second)
        #expect(decisions.records.count == 2)
        #expect(decisions.records[0].identityHash == "AAAAAAAAAAAAAAAA")
        #expect(decisions.records[1].identityHash == "BBBBBBBBBBBBBBBB")
    }

    // MARK: - JSON round-trip

    @Test("InteractionDecisions round-trips through JSON")
    func roundTripJSON() throws {
        let decisions = InteractionDecisions(records: [
            record(identity: "AAAAAAAAAAAAAAAA"),
            record(identity: "BBBBBBBBBBBBBBBB", decision: .rejected),
            record(identity: "CCCCCCCCCCCCCCCC", decision: .acceptedAsConformance)
        ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(decisions)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(InteractionDecisions.self, from: data)
        #expect(decoded == decisions)
    }

    // MARK: - Schema version

    @Test("schemaVersion defaults to 1")
    func defaultSchemaVersion() {
        #expect(InteractionDecisions.empty.schemaVersion == 1)
        #expect(InteractionDecisions.currentSchemaVersion == 1)
    }
}
