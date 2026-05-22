import Foundation
import Testing
@testable import SwiftInferCore

@Suite("VerifyEvidence — data model + Codable round-trip (V1.64.A schema v1)")
struct VerifyEvidenceTests {

    // MARK: - Empty state

    @Test
    func emptyValueHasCurrentSchemaVersionAndNoRecords() {
        #expect(VerifyEvidenceLog.empty.schemaVersion == VerifyEvidenceLog.currentSchemaVersion)
        #expect(VerifyEvidenceLog.empty.records.isEmpty)
    }

    // MARK: - Outcome raw values

    @Test
    func outcomeRawValuesMatchTheSurveyClassificationStrings() {
        // These five strings must stay byte-identical to SwiftInferCLI's
        // SurveyOutcome raw values — the survey writer (V1.64.B) maps
        // one to the other by rawValue round-trip.
        #expect(VerifyEvidenceOutcome.measuredBothPass.rawValue == "measured-bothPass")
        #expect(VerifyEvidenceOutcome.measuredEdgeCaseAdvisory.rawValue == "measured-edgeCaseAdvisory")
        #expect(VerifyEvidenceOutcome.measuredDefaultFails.rawValue == "measured-defaultFails")
        #expect(VerifyEvidenceOutcome.measuredError.rawValue == "measured-error")
        #expect(VerifyEvidenceOutcome.architecturalCoveragePending.rawValue == "architectural-coverage-pending")
        #expect(VerifyEvidenceOutcome.allCases.count == 5)
    }

    // MARK: - Record lookup

    @Test
    func recordLookupReturnsNilForUnknownIdentity() {
        #expect(VerifyEvidenceLog.empty.record(for: "ABCDEF1234567890") == nil)
    }

    @Test
    func recordLookupReturnsTheMatchingRecord() {
        let record = makeEvidence(identity: "ABCDEF1234567890", outcome: .measuredBothPass)
        let log = VerifyEvidenceLog(records: [record])
        #expect(log.record(for: "ABCDEF1234567890") == record)
    }

    // MARK: - upserting (overwrite by identity — latest run wins)

    @Test
    func upsertingNewIdentityAppendsRecord() {
        let next = VerifyEvidenceLog.empty.upserting(makeEvidence(identity: "AAA1111111111111"))
        #expect(next.records.count == 1)
        #expect(next.records[0].identityHash == "AAA1111111111111")
    }

    @Test
    func upsertingExistingIdentityReplacesPriorRecord() {
        let earlier = makeEvidence(identity: "AAA1111111111111", outcome: .architecturalCoveragePending)
        let later = makeEvidence(identity: "AAA1111111111111", outcome: .measuredBothPass)
        let after = VerifyEvidenceLog(records: [earlier]).upserting(later)
        #expect(after.records.count == 1)
        #expect(after.records[0].outcome == .measuredBothPass)
    }

    @Test
    func upsertingPreservesOtherIdentitiesInOriginalOrder() {
        let first = makeEvidence(identity: "AAA1111111111111")
        let second = makeEvidence(identity: "BBB2222222222222")
        let log = VerifyEvidenceLog(records: [first, second])
        let updated = log.upserting(makeEvidence(identity: "AAA1111111111111", outcome: .measuredDefaultFails))
        #expect(updated.records.count == 2)
        // The untouched record keeps its leading position; the upserted
        // record moves to the trailing slot.
        #expect(updated.records[0].identityHash == "BBB2222222222222")
        #expect(updated.records[1].identityHash == "AAA1111111111111")
        #expect(updated.records[1].outcome == .measuredDefaultFails)
    }

    @Test
    func upsertingPreservesSchemaVersion() {
        let log = VerifyEvidenceLog(schemaVersion: 7, records: [])
        let updated = log.upserting(makeEvidence(identity: "AAA1111111111111"))
        #expect(updated.schemaVersion == 7)
    }

    // MARK: - Codable round-trip

    @Test
    func codableRoundTripPreservesEveryField() throws {
        let log = VerifyEvidenceLog(records: [
            makeEvidence(
                identity: "DEADBEEF12345678",
                template: "round-trip",
                outcome: .measuredBothPass,
                detail: "defaultTrials=100 edgeTrials=100 edgeSampled=6"
            ),
            VerifyEvidence(
                identityHash: "CAFEBABE87654321",
                template: "monotonicity",
                outcome: .architecturalCoveragePending,
                detail: nil,
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                swiftInferVersion: "1.64.0"
            )
        ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(VerifyEvidenceLog.self, from: encoder.encode(log))
        #expect(decoded == log)
    }

    @Test
    func nilDetailRoundTripsAsNil() throws {
        let record = VerifyEvidence(
            identityHash: "AAA1111111111111",
            template: "idempotence",
            outcome: .measuredEdgeCaseAdvisory,
            detail: nil,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            swiftInferVersion: "1.64.0"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(VerifyEvidence.self, from: encoder.encode(record))
        #expect(decoded.detail == nil)
        #expect(decoded == record)
    }

    // MARK: - Helpers

    private func makeEvidence(
        identity: String,
        template: String = "round-trip",
        outcome: VerifyEvidenceOutcome = .measuredBothPass,
        detail: String? = "defaultTrials=100 edgeTrials=0 edgeSampled=0"
    ) -> VerifyEvidence {
        VerifyEvidence(
            identityHash: identity,
            template: template,
            outcome: outcome,
            detail: detail,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            swiftInferVersion: "1.64.0"
        )
    }
}

/// V1.69 — `VerifyEvidenceLog.merge` folds per-corpus evidence files
/// into one in-memory aggregate for the `metrics` §17.2 cross-reference
/// under `--decisions` mode. Mirrors `Decisions.merge`'s semantics:
/// identity-keyed, later `capturedAt` wins, order-deterministic output.
@Suite("VerifyEvidenceLog.merge — V1.69 multi-corpus aggregation")
struct VerifyEvidenceLogMergeTests {

    private func makeEvidence(
        identity: String,
        outcome: VerifyEvidenceOutcome = .measuredBothPass,
        capturedAt: Date
    ) -> VerifyEvidence {
        VerifyEvidence(
            identityHash: identity,
            template: "round-trip",
            outcome: outcome,
            detail: nil,
            capturedAt: capturedAt,
            swiftInferVersion: "1.69.0"
        )
    }

    @Test("Disjoint logs merge to the union")
    func disjointMerge() {
        let lhs = VerifyEvidenceLog(records: [
            makeEvidence(identity: "AAA1111111111111", capturedAt: Date(timeIntervalSince1970: 100))
        ])
        let rhs = VerifyEvidenceLog(records: [
            makeEvidence(identity: "BBB2222222222222", capturedAt: Date(timeIntervalSince1970: 200))
        ])
        let merged = lhs.merge(rhs)
        #expect(merged.records.count == 2)
        #expect(Set(merged.records.map(\.identityHash)) == ["AAA1111111111111", "BBB2222222222222"])
    }

    @Test("Overlapping identity: later capturedAt wins")
    func overlapLaterWins() {
        let older = makeEvidence(
            identity: "AAA1111111111111",
            outcome: .measuredDefaultFails,
            capturedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = makeEvidence(
            identity: "AAA1111111111111",
            outcome: .measuredBothPass,
            capturedAt: Date(timeIntervalSince1970: 200)
        )
        let merged = VerifyEvidenceLog(records: [older]).merge(VerifyEvidenceLog(records: [newer]))
        #expect(merged.records.count == 1)
        #expect(merged.records.first?.outcome == .measuredBothPass)
    }

    @Test("Overlapping identity: order-independent — older RHS does not displace newer LHS")
    func overlapOrderIndependent() {
        let older = makeEvidence(
            identity: "AAA1111111111111",
            outcome: .measuredDefaultFails,
            capturedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = makeEvidence(
            identity: "AAA1111111111111",
            outcome: .measuredBothPass,
            capturedAt: Date(timeIntervalSince1970: 200)
        )
        let merged = VerifyEvidenceLog(records: [newer]).merge(VerifyEvidenceLog(records: [older]))
        #expect(merged.records.count == 1)
        #expect(merged.records.first?.outcome == .measuredBothPass)
    }

    @Test("Result is sorted by capturedAt then identityHash")
    func resultIsSorted() {
        let merged = VerifyEvidenceLog(records: [
            makeEvidence(identity: "CCC3333333333333", capturedAt: Date(timeIntervalSince1970: 300))
        ]).merge(VerifyEvidenceLog(records: [
            makeEvidence(identity: "AAA1111111111111", capturedAt: Date(timeIntervalSince1970: 100)),
            makeEvidence(identity: "BBB2222222222222", capturedAt: Date(timeIntervalSince1970: 200))
        ]))
        #expect(merged.records.map(\.identityHash) == [
            "AAA1111111111111", "BBB2222222222222", "CCC3333333333333"
        ])
    }

    @Test("Schema version is the max of the two inputs")
    func schemaVersionMaxes() {
        let lhs = VerifyEvidenceLog(schemaVersion: 1, records: [])
        let rhs = VerifyEvidenceLog(schemaVersion: 3, records: [])
        #expect(lhs.merge(rhs).schemaVersion == 3)
        #expect(rhs.merge(lhs).schemaVersion == 3)
    }

    @Test("Empty merged with empty is empty")
    func emptyMergeEmpty() {
        #expect(VerifyEvidenceLog.empty.merge(.empty).records.isEmpty)
    }
}
