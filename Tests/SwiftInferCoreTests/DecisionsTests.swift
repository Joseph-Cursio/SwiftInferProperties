import Foundation
import Testing
@testable import SwiftInferCore

@Suite("Decisions — data model + Codable round-trip (M6.1)")
struct DecisionsTests {

    // MARK: - Empty state

    @Test
    func emptyValueHasCurrentSchemaVersionAndNoRecords() {
        #expect(Decisions.empty.schemaVersion == Decisions.currentSchemaVersion)
        #expect(Decisions.empty.records.isEmpty)
    }

    // MARK: - Record lookup

    @Test
    func recordLookupReturnsNilForUnknownIdentity() {
        #expect(Decisions.empty.record(for: "ABCDEF1234567890") == nil)
    }

    @Test
    func recordLookupReturnsTheMatchingRecord() {
        let record = makeRecord(identity: "ABCDEF1234567890", decision: .accepted)
        let decisions = Decisions(records: [record])
        #expect(decisions.record(for: "ABCDEF1234567890") == record)
    }

    // MARK: - upserting (open decision #7 — overwrite by identity)

    @Test
    func upsertingNewIdentityAppendsRecord() {
        let initial = Decisions.empty
        let next = initial.upserting(makeRecord(identity: "AAA1111111111111"))
        #expect(next.records.count == 1)
        #expect(next.records[0].identityHash == "AAA1111111111111")
    }

    @Test
    func upsertingExistingIdentityReplacesPriorRecord() {
        let earlier = makeRecord(identity: "AAA1111111111111", decision: .skipped)
        let later = makeRecord(identity: "AAA1111111111111", decision: .accepted)
        let after = Decisions(records: [earlier]).upserting(later)
        #expect(after.records.count == 1)
        #expect(after.records[0].decision == .accepted)
    }

    @Test
    func upsertingPreservesOtherIdentitiesInOriginalOrder() {
        let alpha = makeRecord(identity: "AAA1111111111111", template: "idempotence")
        let beta = makeRecord(identity: "BBB2222222222222", template: "round-trip")
        let gamma = makeRecord(identity: "AAA1111111111111", template: "idempotence", decision: .rejected)
        let after = Decisions(records: [alpha, beta]).upserting(gamma)
        #expect(after.records.count == 2)
        // Beta stays where it was; the upserted record lands at the end.
        #expect(after.records[0].identityHash == "BBB2222222222222")
        #expect(after.records[1].identityHash == "AAA1111111111111")
        #expect(after.records[1].decision == .rejected)
    }

    // MARK: - Codable round-trip

    @Test
    func codableRoundTripPreservesAllFields() throws {
        let record = DecisionRecord(
            identityHash: "DEADBEEF12345678",
            template: "round-trip",
            scoreAtDecision: 90,
            tier: .strong,
            decision: .accepted,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            signalWeights: [
                SignalSnapshot(kind: "exactNameMatch", weight: 40),
                SignalSnapshot(kind: "typeSymmetrySignature", weight: 30)
            ]
        )
        let original = Decisions(records: [record])
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Decisions.self, from: encoded)
        #expect(decoded == original)
    }

    @Test
    func decisionEnumRoundTripsThroughItsRawString() throws {
        for decision in Decision.allCases {
            let data = try JSONEncoder().encode(decision)
            let decoded = try JSONDecoder().decode(Decision.self, from: data)
            #expect(decoded == decision)
        }
    }

    @Test
    func tierEnumIsCodable() throws {
        // Additive Codable conformance was added to `Tier` for the
        // M6.1 schema. Re-verify here so a future change to Tier's
        // representation can't silently break decisions.json
        // backward compatibility.
        for tier in Tier.allCases {
            let data = try JSONEncoder().encode(tier)
            let decoded = try JSONDecoder().decode(Tier.self, from: data)
            #expect(decoded == tier)
        }
    }

    // MARK: - Helpers

    private func makeRecord(
        identity: String,
        template: String = "idempotence",
        decision: Decision = .accepted
    ) -> DecisionRecord {
        DecisionRecord(
            identityHash: identity,
            template: template,
            scoreAtDecision: 90,
            tier: .strong,
            decision: decision,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            signalWeights: []
        )
    }
}
