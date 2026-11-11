import Foundation
@testable import SwiftInferCore
import Testing

// V1.72.B — data-model tests for the post-acceptance-outcomes shape:
// outcome rawValues stay stable (the §17.2 metric and tests both key on
// them), upsert-by-identity behaves like VerifyEvidenceLog's, and
// merge orders deterministically.

@Suite("PostAcceptanceOutcome — V1.72.B data model + upsert + merge")
struct PostAcceptanceOutcomeTests {

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    private func outcome(
        identity: String,
        kind: PostAcceptanceOutcomeKind = .stillPasses,
        checkedAt iso: String = "2026-05-15T10:00:00Z"
    ) throws -> PostAcceptanceOutcome {
        PostAcceptanceOutcome(
            identityHash: identity,
            template: "round-trip",
            outcome: kind,
            detail: nil,
            originalAcceptedAt: try date("2026-05-14T10:00:00Z"),
            checkedAt: try date(iso),
            swiftInferVersion: "1.72.0"
        )
    }

    // MARK: - Outcome raw values

    @Test("outcome rawValues match the documented strings — the metric joins on these")
    func outcomeRawValues() {
        #expect(PostAcceptanceOutcomeKind.stillPasses.rawValue == "still-passes")
        #expect(PostAcceptanceOutcomeKind.nowFails.rawValue == "now-fails")
        #expect(PostAcceptanceOutcomeKind.obsolete.rawValue == "obsolete")
        #expect(PostAcceptanceOutcomeKind.error.rawValue == "error")
        #expect(PostAcceptanceOutcomeKind.allCases.count == 4)
    }

    // MARK: - Empty state

    @Test
    func emptyLogHasCurrentSchemaAndNoRecords() {
        #expect(PostAcceptanceOutcomeLog.empty.schemaVersion == PostAcceptanceOutcomeLog.currentSchemaVersion)
        #expect(PostAcceptanceOutcomeLog.empty.records.isEmpty)
    }

    // MARK: - record(for:)

    @Test
    func recordLookupReturnsNilForUnknownIdentity() {
        #expect(PostAcceptanceOutcomeLog.empty.record(for: "ABCDEF1234567890") == nil)
    }

    @Test
    func recordLookupReturnsTheMatchingRecord() throws {
        let target = try outcome(identity: "AAA1111111111111")
        let log = PostAcceptanceOutcomeLog(records: [target])
        #expect(log.record(for: "AAA1111111111111") == target)
    }

    // MARK: - upserting

    @Test
    func upsertingNewIdentityAppendsRecord() throws {
        let updated = PostAcceptanceOutcomeLog.empty.upserting(try outcome(identity: "AAA1111111111111"))
        #expect(updated.records.count == 1)
        #expect(updated.records[0].identityHash == "AAA1111111111111")
    }

    @Test
    func upsertingExistingIdentityReplacesPriorRecord() throws {
        let earlier = try outcome(identity: "AAA1111111111111", kind: .stillPasses)
        let later = try outcome(identity: "AAA1111111111111", kind: .nowFails)
        let after = PostAcceptanceOutcomeLog(records: [earlier]).upserting(later)
        #expect(after.records.count == 1)
        #expect(after.records[0].outcome == .nowFails)
    }

    @Test("upserting moves the updated record to the trailing slot — stable diff for prior records")
    func upsertingPreservesOtherIdentitiesInOrder() throws {
        let first = try outcome(identity: "AAA1111111111111")
        let second = try outcome(identity: "BBB2222222222222")
        let log = PostAcceptanceOutcomeLog(records: [first, second])
        let updated = log.upserting(try outcome(identity: "AAA1111111111111", kind: .nowFails))
        #expect(updated.records.map(\.identityHash) == ["BBB2222222222222", "AAA1111111111111"])
        #expect(updated.records[1].outcome == .nowFails)
    }

    // MARK: - merge

    @Test("merge keeps the later checkedAt on collision")
    func mergeLatestCheckedAtWins() throws {
        let earlier = try outcome(identity: "AAA1111111111111", kind: .stillPasses, checkedAt: "2026-05-15T10:00:00Z")
        let later = try outcome(identity: "AAA1111111111111", kind: .nowFails, checkedAt: "2026-05-16T10:00:00Z")
        let merged = PostAcceptanceOutcomeLog(records: [earlier]).merge(
            PostAcceptanceOutcomeLog(records: [later])
        )
        #expect(merged.records.count == 1)
        #expect(merged.records[0].outcome == .nowFails)
    }

    @Test("merge sorts by checkedAt then identityHash deterministically regardless of input order")
    func mergeIsDeterministicallyOrdered() throws {
        let alpha = try outcome(identity: "AAA1111111111111", checkedAt: "2026-05-15T10:00:00Z")
        let beta = try outcome(identity: "BBB2222222222222", checkedAt: "2026-05-15T11:00:00Z")
        let leftFirst = PostAcceptanceOutcomeLog(records: [alpha]).merge(
            PostAcceptanceOutcomeLog(records: [beta])
        )
        let rightFirst = PostAcceptanceOutcomeLog(records: [beta]).merge(
            PostAcceptanceOutcomeLog(records: [alpha])
        )
        #expect(leftFirst == rightFirst)
        #expect(leftFirst.records.map(\.identityHash) == ["AAA1111111111111", "BBB2222222222222"])
    }

    // MARK: - Codable round-trip

    @Test("PostAcceptanceOutcome round-trips through JSONEncoder/Decoder")
    func codableRoundTrip() throws {
        let original = PostAcceptanceOutcome(
            identityHash: "AAA1111111111111",
            template: "idempotence",
            outcome: .nowFails,
            detail: "defaultFails",
            originalAcceptedAt: try date("2026-05-14T10:00:00Z"),
            checkedAt: try date("2026-05-15T10:00:00Z"),
            swiftInferVersion: "1.72.0"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PostAcceptanceOutcome.self, from: data)
        #expect(decoded == original)
    }
}
