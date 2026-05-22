import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// V1.33.B — `IndexStore` JSON persistence + upsert semantics.
@Suite("IndexStore — V1.33.B JSON persistence")
struct IndexStoreTests {

    // MARK: - Fixtures

    private static let entry1 = SemanticIndexEntry(
        identityHash: "0x0000000000000001",
        templateName: "round-trip",
        typeName: "Foo",
        score: 35,
        tier: "Possible",
        primaryFunctionName: "encode(_:)",
        location: "/a.swift:10",
        decision: "accept",
        decisionAt: "2026-05-11T12:00:00Z",
        firstSeenAt: "2026-05-11T00:00:00Z",
        lastSeenAt: "2026-05-11T12:00:00Z"
    )

    private static let entry2 = SemanticIndexEntry(
        identityHash: "0x0000000000000002",
        templateName: "idempotence",
        typeName: "Bar",
        score: 30,
        tier: "Possible",
        primaryFunctionName: "normalize(_:)",
        location: "/b.swift:20",
        decision: nil,
        decisionAt: nil,
        firstSeenAt: "2026-05-11T00:00:00Z",
        lastSeenAt: "2026-05-11T12:00:00Z"
    )

    // MARK: - Round-trip

    @Test("V1.33.B — Index JSON encode + decode round-trips bit-for-bit")
    func indexRoundTrips() throws {
        let original = IndexStore.Index(
            schemaVersion: 1,
            updatedAt: "2026-05-11T12:00:00Z",
            entries: [Self.entry1, Self.entry2]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(IndexStore.Index.self, from: data)
        #expect(decoded == original)
    }

    @Test("V1.33.B — save + load preserves the index")
    func saveLoadPreserves() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("v1.33-indexstore-tests-\(UUID().uuidString)")
        let path = tempDir.appendingPathComponent("index.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let index = IndexStore.Index(
            updatedAt: "2026-05-11T12:00:00Z",
            entries: [Self.entry1, Self.entry2]
        )
        try IndexStore.save(index, to: path)

        let loadResult = IndexStore.load(
            from: path,
            nowTimestamp: "2026-05-11T13:00:00Z"
        )
        #expect(loadResult.warnings.isEmpty)
        #expect(loadResult.index == index)
    }

    @Test("V1.33.B — load on missing path returns empty index without warning")
    func loadMissingPathReturnsEmpty() {
        let nonexistent = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).json")
        let result = IndexStore.load(
            from: nonexistent,
            nowTimestamp: "2026-05-11T12:00:00Z"
        )
        #expect(result.warnings.isEmpty)
        #expect(result.index.entries.isEmpty)
        #expect(result.index.schemaVersion == IndexStore.currentSchemaVersion)
        #expect(result.index.updatedAt == "2026-05-11T12:00:00Z")
    }

    @Test("V1.33.B — load on malformed file emits warning + returns empty")
    func loadMalformedReturnsEmptyWithWarning() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("v1.33-indexstore-malformed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let path = tempDir.appendingPathComponent("index.json")
        try "not-json".write(to: path, atomically: true, encoding: .utf8)

        let result = IndexStore.load(
            from: path,
            nowTimestamp: "2026-05-11T12:00:00Z"
        )
        #expect(!result.warnings.isEmpty)
        #expect(result.index.entries.isEmpty)
    }

    // MARK: - Upsert

    @Test("V1.33.B — upsert into empty index inserts all entries with sorted hashes")
    func upsertIntoEmpty() {
        let existing = IndexStore.Index.empty(at: "2026-05-11T00:00:00Z")
        let result = IndexStore.upsert(
            [Self.entry2, Self.entry1],   // out of hash order on purpose
            into: existing,
            at: "2026-05-11T12:00:00Z"
        )
        #expect(result.entries.count == 2)
        #expect(result.entries.map(\.identityHash) == [
            "0x0000000000000001",
            "0x0000000000000002"
        ])
        #expect(result.updatedAt == "2026-05-11T12:00:00Z")
    }

    @Test("V1.33.B — upsert preserves firstSeenAt from existing rows")
    func upsertPreservesFirstSeenAt() {
        let initial = IndexStore.Index(
            updatedAt: "2026-05-11T00:00:00Z",
            entries: [Self.entry1]   // firstSeenAt = 2026-05-11T00:00:00Z
        )
        let fresh = SemanticIndexEntry(
            identityHash: Self.entry1.identityHash,
            templateName: Self.entry1.templateName,
            typeName: Self.entry1.typeName,
            score: 70,                  // changed
            tier: "Likely",             // changed
            primaryFunctionName: Self.entry1.primaryFunctionName,
            location: Self.entry1.location,
            decision: "reject",         // changed
            decisionAt: "2026-05-12T01:00:00Z",
            firstSeenAt: "2026-05-12T00:00:00Z",  // newer, but should be IGNORED
            lastSeenAt: "2026-05-12T00:00:00Z"
        )
        let result = IndexStore.upsert([fresh], into: initial, at: "2026-05-12T00:00:00Z")
        #expect(result.entries.count == 1)
        let merged = result.entries[0]
        #expect(merged.firstSeenAt == "2026-05-11T00:00:00Z", "firstSeenAt must be preserved")
        #expect(merged.lastSeenAt == "2026-05-12T00:00:00Z")
        #expect(merged.score == 70)
        #expect(merged.tier == "Likely")
        #expect(merged.decision == "reject")
    }

    @Test("V1.33.B — upsert keeps historical entries not in freshEntries")
    func upsertKeepsHistorical() {
        let initial = IndexStore.Index(
            updatedAt: "2026-05-11T00:00:00Z",
            entries: [Self.entry1, Self.entry2]
        )
        // Only entry1 is fresh; entry2 must be preserved as historical.
        let result = IndexStore.upsert([Self.entry1], into: initial, at: "2026-05-12T00:00:00Z")
        #expect(result.entries.count == 2)
        #expect(result.entries.contains { $0.identityHash == Self.entry2.identityHash })
    }
}
