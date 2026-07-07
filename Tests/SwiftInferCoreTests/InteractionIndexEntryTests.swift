import Foundation
@testable import SwiftInferCore
import Testing

/// V1.141.A — `InteractionIndexEntry` data model tests. Round-trip JSON,
/// upsert `updated(from:)` semantics (firstSeenAt + identity columns
/// preserved), and structural equality. The interaction analog of
/// `SemanticIndexEntryTests`.
@Suite("InteractionIndexEntry — V1.141.A data model")
struct InteractionIndexEntryTests {

    private static let exampleEntry = InteractionIndexEntry(
        identityHash: "0xBC43359C0574816B",
        family: "referential-integrity",
        reducerQualifiedName: "LibraryFeature.reduce",
        stateTypeName: "State",
        actionTypeName: "Action",
        predicate: "state.selectedBookID == nil || state.books.contains { $0.id == state.selectedBookID }",
        location: "/foo/LibraryFeature.swift:42",
        moduleName: "Library",
        score: 30,
        tier: "Possible",
        decision: "accept",
        decisionAt: "2026-06-14T12:34:56Z",
        firstSeenAt: "2026-06-13T00:00:00Z",
        lastSeenAt: "2026-06-14T12:34:56Z"
    )

    // MARK: - JSON round-trip

    @Test("V1.141.A — JSON encode + decode round-trips bit-for-bit")
    func jsonRoundTripBitForBit() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Self.exampleEntry)
        let decoded = try JSONDecoder().decode(InteractionIndexEntry.self, from: data)
        #expect(decoded == Self.exampleEntry)
    }

    @Test("V1.141.A — nil decision + nil decisionAt round-trip as nil")
    func nilDecisionRoundTrips() throws {
        let untriaged = InteractionIndexEntry(
            identityHash: "0xDEADBEEF12345678",
            family: "idempotence",
            reducerQualifiedName: "NavFeature.reduce",
            stateTypeName: "State",
            actionTypeName: "Action",
            predicate: "reduce(reduce(s, .dismiss), .dismiss) == reduce(s, .dismiss)",
            location: "/a.swift:1",
            moduleName: nil,
            score: 40,
            tier: "Likely",
            decision: nil,
            decisionAt: nil,
            firstSeenAt: "2026-06-13T00:00:00Z",
            lastSeenAt: "2026-06-13T00:00:00Z"
        )
        let data = try JSONEncoder().encode(untriaged)
        let decoded = try JSONDecoder().decode(InteractionIndexEntry.self, from: data)
        #expect(decoded.decision == nil)
        #expect(decoded.decisionAt == nil)
        #expect(decoded == untriaged)
    }

    @Test("V1.141.A — nil moduleName (single-target) round-trips")
    func nilModuleNameRoundTrips() throws {
        var entry = Self.exampleEntry
        entry = InteractionIndexEntry(
            identityHash: entry.identityHash,
            family: entry.family,
            reducerQualifiedName: entry.reducerQualifiedName,
            stateTypeName: entry.stateTypeName,
            actionTypeName: entry.actionTypeName,
            predicate: entry.predicate,
            location: entry.location,
            moduleName: nil,
            score: entry.score,
            tier: entry.tier,
            decision: entry.decision,
            decisionAt: entry.decisionAt,
            firstSeenAt: entry.firstSeenAt,
            lastSeenAt: entry.lastSeenAt
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(InteractionIndexEntry.self, from: data)
        #expect(decoded.moduleName == nil)
        #expect(decoded == entry)
    }

    // MARK: - updated(from:) semantics

    @Test("V1.141.A — updated(from:) preserves firstSeenAt from self, refreshes mutable columns")
    func updatedPreservesFirstSeenAt() {
        let original = Self.exampleEntry
        let newer = InteractionIndexEntry(
            identityHash: original.identityHash,
            family: original.family,
            reducerQualifiedName: original.reducerQualifiedName,
            stateTypeName: original.stateTypeName,
            actionTypeName: original.actionTypeName,
            predicate: original.predicate,
            location: "/moved/LibraryFeature.swift:99",
            moduleName: "LibraryRenamed",
            score: 80,
            tier: "Verified",
            decision: "reject",
            decisionAt: "2026-06-15T01:00:00Z",
            firstSeenAt: "2026-06-15T00:00:00Z",   // newer firstSeenAt — must be ignored
            lastSeenAt: "2026-06-15T00:00:00Z"
        )
        let merged = original.updated(from: newer)
        #expect(merged.firstSeenAt == original.firstSeenAt, "firstSeenAt must be preserved from self")
        #expect(merged.lastSeenAt == newer.lastSeenAt, "lastSeenAt must update from other")
        #expect(merged.location == "/moved/LibraryFeature.swift:99")
        #expect(merged.moduleName == "LibraryRenamed")
        #expect(merged.score == 80)
        #expect(merged.tier == "Verified")
        #expect(merged.decision == "reject")
        #expect(merged.decisionAt == "2026-06-15T01:00:00Z")
    }

    @Test("V1.141.A — updated(from:) preserves identity columns (hash, family, reducer, state, action, predicate)")
    func updatedPreservesIdentityColumns() {
        let original = Self.exampleEntry
        let newer = InteractionIndexEntry(
            identityHash: "0xDIFFERENTHASH00",   // these don't change in practice
            family: "conservation",
            reducerQualifiedName: "OtherFeature.reduce",
            stateTypeName: "OtherState",
            actionTypeName: "OtherAction",
            predicate: "state.count == state.items.count",
            location: original.location,
            moduleName: original.moduleName,
            score: 55,
            tier: "Strong",
            decision: nil,
            decisionAt: nil,
            firstSeenAt: "2026-06-15T00:00:00Z",
            lastSeenAt: "2026-06-15T00:00:00Z"
        )
        let merged = original.updated(from: newer)
        // Identity columns come from self (immutable across upserts).
        #expect(merged.identityHash == original.identityHash)
        #expect(merged.family == original.family)
        #expect(merged.reducerQualifiedName == original.reducerQualifiedName)
        #expect(merged.stateTypeName == original.stateTypeName)
        #expect(merged.actionTypeName == original.actionTypeName)
        #expect(merged.predicate == original.predicate)
    }

    // MARK: - Equality semantics

    @Test("V1.141.A — Equatable conformance is structural")
    func equatableIsStructural() {
        let entry1 = Self.exampleEntry
        let entry2 = InteractionIndexEntry(
            identityHash: entry1.identityHash,
            family: entry1.family,
            reducerQualifiedName: entry1.reducerQualifiedName,
            stateTypeName: entry1.stateTypeName,
            actionTypeName: entry1.actionTypeName,
            predicate: entry1.predicate,
            location: entry1.location,
            moduleName: entry1.moduleName,
            score: entry1.score,
            tier: entry1.tier,
            decision: entry1.decision,
            decisionAt: entry1.decisionAt,
            firstSeenAt: entry1.firstSeenAt,
            lastSeenAt: entry1.lastSeenAt
        )
        #expect(entry1 == entry2)
        // Change one field → not equal.
        let entry3 = InteractionIndexEntry(
            identityHash: entry1.identityHash,
            family: entry1.family,
            reducerQualifiedName: entry1.reducerQualifiedName,
            stateTypeName: entry1.stateTypeName,
            actionTypeName: entry1.actionTypeName,
            predicate: entry1.predicate,
            location: entry1.location,
            moduleName: entry1.moduleName,
            score: 99,
            tier: entry1.tier,
            decision: entry1.decision,
            decisionAt: entry1.decisionAt,
            firstSeenAt: entry1.firstSeenAt,
            lastSeenAt: entry1.lastSeenAt
        )
        #expect(entry1 != entry3)
    }
}
