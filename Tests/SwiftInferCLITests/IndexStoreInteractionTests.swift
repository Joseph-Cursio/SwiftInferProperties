import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// V1.141 — `IndexStore` interaction-surface persistence + upsert.
/// Split from `IndexStoreTests` (the algebraic surface) so each suite
/// stays under SwiftLint's `type_body_length` cap; same store, disjoint
/// entry type.
@Suite("IndexStore — V1.141 interaction surface")
struct IndexStoreInteractionTests {

    // MARK: - Fixtures

    private static let interaction1 = InteractionIndexEntry(
        identityHash: "0x00000000000000A1",
        family: "idempotence",
        reducerQualifiedName: "NavFeature.reduce",
        stateTypeName: "State",
        actionTypeName: "Action",
        predicate: "reduce(reduce(s, .dismiss), .dismiss) == reduce(s, .dismiss)",
        location: "/nav.swift:10",
        moduleName: nil,
        score: 40,
        tier: "Likely",
        decision: nil,
        decisionAt: nil,
        firstSeenAt: "2026-06-13T00:00:00Z",
        lastSeenAt: "2026-06-13T12:00:00Z"
    )

    private static let interaction2 = InteractionIndexEntry(
        identityHash: "0x00000000000000A2",
        family: "referential-integrity",
        reducerQualifiedName: "LibraryFeature.reduce",
        stateTypeName: "State",
        actionTypeName: "Action",
        predicate: "state.selectedBookID == nil || state.books.contains { $0.id == state.selectedBookID }",
        location: "/library.swift:20",
        moduleName: "Library",
        score: 30,
        tier: "Possible",
        decision: "accept",
        decisionAt: "2026-06-14T01:00:00Z",
        firstSeenAt: "2026-06-13T00:00:00Z",
        lastSeenAt: "2026-06-14T01:00:00Z"
    )

    /// A minimal algebraic entry, used to prove the two surfaces don't
    /// clobber each other across upserts.
    private static let algebraicEntry = SemanticIndexEntry(
        identityHash: "0x0000000000000001",
        templateName: "round-trip",
        typeName: "Foo",
        score: 35,
        tier: "Possible",
        primaryFunctionName: "encode(_:)",
        location: "/a.swift:10",
        firstSeenAt: "2026-05-11T00:00:00Z",
        lastSeenAt: "2026-05-11T12:00:00Z"
    )

    // MARK: - Round-trip + back-compat

    @Test("V1.141 — Index with interactionEntries round-trips through JSON")
    func indexWithInteractionEntriesRoundTrips() throws {
        let original = IndexStore.Index(
            updatedAt: "2026-06-14T12:00:00Z",
            entries: [Self.algebraicEntry],
            interactionEntries: [Self.interaction1, Self.interaction2]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(IndexStore.Index.self, from: data)
        #expect(decoded == original)
        #expect(decoded.interactionEntries.count == 2)
    }

    @Test("V1.141 — a pre-v5 index (no interactionEntries key) decodes to an empty array")
    func preV5IndexDecodesWithEmptyInteractionEntries() throws {
        // A v1–v4 file has no `interactionEntries` key; custom `init(from:)`
        // must default it to `[]` rather than fail the decode. This v4 file
        // also carries a typeShapes key to prove both optionals coexist.
        let legacyJSON = #"""
        {"schemaVersion":4,"updatedAt":"2026-05-11T12:00:00Z","entries":[],"typeShapes":{}}
        """#
        let decoded = try JSONDecoder().decode(IndexStore.Index.self, from: Data(legacyJSON.utf8))
        #expect(decoded.interactionEntries.isEmpty)
        #expect(decoded.schemaVersion == 4)
    }

    // MARK: - upsertInteraction

    @Test("V1.141 — upsertInteraction into empty index inserts with sorted hashes")
    func upsertInteractionIntoEmpty() {
        let existing = IndexStore.Index.empty(at: "2026-06-13T00:00:00Z")
        let result = IndexStore.upsertInteraction(
            [Self.interaction2, Self.interaction1],   // out of hash order on purpose
            into: existing,
            at: "2026-06-14T12:00:00Z"
        )
        #expect(result.interactionEntries.map(\.identityHash) == [
            "0x00000000000000A1",
            "0x00000000000000A2"
        ])
        #expect(result.updatedAt == "2026-06-14T12:00:00Z")
    }

    @Test("V1.141 — upsertInteraction preserves firstSeenAt + keeps historical + leaves algebraic entries")
    func upsertInteractionPreservesAndKeeps() {
        let initial = IndexStore.Index(
            updatedAt: "2026-06-13T00:00:00Z",
            entries: [Self.algebraicEntry],   // algebraic entry must survive untouched
            interactionEntries: [Self.interaction1, Self.interaction2]
        )
        let fresh = InteractionIndexEntry(
            identityHash: Self.interaction1.identityHash,
            family: Self.interaction1.family,
            reducerQualifiedName: Self.interaction1.reducerQualifiedName,
            stateTypeName: Self.interaction1.stateTypeName,
            actionTypeName: Self.interaction1.actionTypeName,
            predicate: Self.interaction1.predicate,
            location: Self.interaction1.location,
            moduleName: Self.interaction1.moduleName,
            score: 90,                    // changed
            tier: "Verified",             // changed
            decision: "accept",          // changed
            decisionAt: "2026-06-15T01:00:00Z",
            firstSeenAt: "2026-06-15T00:00:00Z",   // newer, but must be IGNORED
            lastSeenAt: "2026-06-15T00:00:00Z"
        )
        let result = IndexStore.upsertInteraction([fresh], into: initial, at: "2026-06-15T00:00:00Z")
        // interaction2 preserved as historical; algebraic entry untouched.
        #expect(result.interactionEntries.count == 2)
        #expect(result.entries == [Self.algebraicEntry])
        let merged = result.interactionEntries.first { $0.identityHash == fresh.identityHash }
        #expect(merged?.firstSeenAt == "2026-06-13T00:00:00Z", "firstSeenAt must be preserved")
        #expect(merged?.lastSeenAt == "2026-06-15T00:00:00Z")
        #expect(merged?.score == 90)
        #expect(merged?.tier == "Verified")
        #expect(merged?.decision == "accept")
    }

    @Test("V1.141 — algebraic upsert preserves existing interactionEntries")
    func algebraicUpsertPreservesInteractionEntries() {
        let initial = IndexStore.Index(
            updatedAt: "2026-06-13T00:00:00Z",
            entries: [],
            interactionEntries: [Self.interaction1]
        )
        let result = IndexStore.upsert([Self.algebraicEntry], into: initial, at: "2026-06-14T00:00:00Z")
        #expect(result.entries.count == 1)
        #expect(result.interactionEntries == [Self.interaction1])
    }
}
