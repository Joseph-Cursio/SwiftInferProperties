import Foundation
import Testing
@testable import SwiftInferCore

@Suite("Baseline — data model + Codable round-trip (M6.2)")
struct BaselineTests {

    // MARK: - Empty state

    @Test
    func emptyValueHasCurrentSchemaVersionAndNoEntries() {
        #expect(Baseline.empty.schemaVersion == Baseline.currentSchemaVersion)
        #expect(Baseline.empty.entries.isEmpty)
    }

    // MARK: - Lookup

    @Test
    func containsReturnsFalseForUnknownIdentity() {
        #expect(Baseline.empty.contains(identityHash: "ABCDEF1234567890") == false)
    }

    @Test
    func containsReturnsTrueForRegisteredIdentity() {
        let entry = makeEntry(identity: "ABCDEF1234567890")
        let baseline = Baseline(entries: [entry])
        #expect(baseline.contains(identityHash: "ABCDEF1234567890"))
    }

    @Test
    func entryLookupReturnsNilForUnknownIdentity() {
        #expect(Baseline.empty.entry(for: "ABCDEF1234567890") == nil)
    }

    @Test
    func entryLookupReturnsTheMatchingEntry() {
        let entry = makeEntry(identity: "ABCDEF1234567890", template: "round-trip")
        let baseline = Baseline(entries: [entry])
        #expect(baseline.entry(for: "ABCDEF1234567890") == entry)
    }

    // MARK: - Codable round-trip

    @Test
    func codableRoundTripPreservesAllFields() throws {
        let entry = BaselineEntry(
            identityHash: "DEADBEEF12345678",
            template: "idempotence",
            scoreAtSnapshot: 90,
            tier: .strong
        )
        let original = Baseline(entries: [entry])
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Baseline.self, from: encoded)
        #expect(decoded == original)
    }

    @Test
    func codableRoundTripPreservesEntryOrder() throws {
        let alpha = makeEntry(identity: "AAA1111111111111", template: "idempotence")
        let beta = makeEntry(identity: "BBB2222222222222", template: "round-trip")
        let original = Baseline(entries: [alpha, beta])
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Baseline.self, from: encoded)
        #expect(decoded.entries.map(\.identityHash) == ["AAA1111111111111", "BBB2222222222222"])
    }

    // MARK: - Helpers

    private func makeEntry(
        identity: String,
        template: String = "idempotence"
    ) -> BaselineEntry {
        BaselineEntry(
            identityHash: identity,
            template: template,
            scoreAtSnapshot: 90,
            tier: .strong
        )
    }
}
