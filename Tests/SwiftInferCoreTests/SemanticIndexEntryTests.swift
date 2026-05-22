import Foundation
@testable import SwiftInferCore
import Testing

/// V1.33.A — `SemanticIndexEntry` data model tests. Round-trip JSON,
/// upsert `updated(from:)` semantics, identity-hash key equality.
@Suite("SemanticIndexEntry — V1.33.A data model")
struct SemanticIndexEntryTests {

    private static let exampleEntry = SemanticIndexEntry(
        identityHash: "0xBC43359C0574816B",
        templateName: "round-trip",
        typeName: "_HashTable.UnsafeHandle",
        score: 35,
        tier: "Possible",
        primaryFunctionName: "_value(forBucketContents:)",
        location: "/foo/bar/_HashTable+UnsafeHandle.swift:201",
        decision: "accept",
        decisionAt: "2026-05-11T12:34:56Z",
        firstSeenAt: "2026-05-10T00:00:00Z",
        lastSeenAt: "2026-05-11T12:34:56Z"
    )

    // MARK: - JSON round-trip

    @Test("V1.33.A — JSON encode + decode round-trips bit-for-bit")
    func jsonRoundTripBitForBit() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Self.exampleEntry)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SemanticIndexEntry.self, from: data)
        #expect(decoded == Self.exampleEntry)
    }

    @Test("V1.33.A — nil decision + nil decisionAt round-trip as nil")
    func nilDecisionRoundTrips() throws {
        let untriaged = SemanticIndexEntry(
            identityHash: "0xDEADBEEF12345678",
            templateName: "idempotence",
            typeName: "Foo",
            score: 30,
            tier: "Possible",
            primaryFunctionName: "normalize(_:)",
            location: "/a.swift:1",
            decision: nil,
            decisionAt: nil,
            firstSeenAt: "2026-05-11T00:00:00Z",
            lastSeenAt: "2026-05-11T00:00:00Z"
        )
        let data = try JSONEncoder().encode(untriaged)
        let decoded = try JSONDecoder().decode(SemanticIndexEntry.self, from: data)
        // The default JSONEncoder omits keys for nil Optionals; the
        // JSONDecoder fills them back as nil. Either omitted-key or
        // explicit-null is acceptable on the wire — the round-trip
        // contract is what matters.
        #expect(decoded.decision == nil)
        #expect(decoded.decisionAt == nil)
        #expect(decoded == untriaged)
    }

    @Test("V1.33.A — nil typeName (free function) round-trips")
    func nilTypeNameRoundTrips() throws {
        let freeFunc = SemanticIndexEntry(
            identityHash: "0xAAAA1111BBBB2222",
            templateName: "monotonicity",
            typeName: nil,
            score: 25,
            tier: "Possible",
            primaryFunctionName: "log(_:)",
            location: "/math.swift:10",
            decision: nil,
            decisionAt: nil,
            firstSeenAt: "2026-05-11T00:00:00Z",
            lastSeenAt: "2026-05-11T00:00:00Z"
        )
        let data = try JSONEncoder().encode(freeFunc)
        let decoded = try JSONDecoder().decode(SemanticIndexEntry.self, from: data)
        #expect(decoded.typeName == nil)
        #expect(decoded == freeFunc)
    }

    // MARK: - updated(from:) semantics

    @Test("V1.33.A — updated(from:) preserves firstSeenAt from self")
    func updatedPreservesFirstSeenAt() {
        let original = Self.exampleEntry
        let newer = SemanticIndexEntry(
            identityHash: original.identityHash,
            templateName: original.templateName,
            typeName: original.typeName,
            score: 40,
            tier: "Likely",
            primaryFunctionName: original.primaryFunctionName,
            location: original.location,
            decision: "reject",
            decisionAt: "2026-05-12T01:00:00Z",
            firstSeenAt: "2026-05-12T00:00:00Z",   // newer firstSeenAt
            lastSeenAt: "2026-05-12T00:00:00Z"
        )
        let merged = original.updated(from: newer)
        #expect(merged.firstSeenAt == original.firstSeenAt, "firstSeenAt must be preserved from self")
        #expect(merged.lastSeenAt == newer.lastSeenAt, "lastSeenAt must update from other")
        #expect(merged.score == 40)
        #expect(merged.tier == "Likely")
        #expect(merged.decision == "reject")
        #expect(merged.decisionAt == "2026-05-12T01:00:00Z")
    }

    @Test("V1.33.A — updated(from:) preserves identity columns (identityHash, templateName, typeName)")
    func updatedPreservesIdentityColumns() {
        let original = Self.exampleEntry
        let newer = SemanticIndexEntry(
            identityHash: "0xDIFFERENT_HASH",      // these don't change in practice
            templateName: "different",
            typeName: "DifferentType",
            score: 99,
            tier: "Strong",
            primaryFunctionName: "different",
            location: "/elsewhere.swift:1",
            decision: nil,
            decisionAt: nil,
            firstSeenAt: "2026-05-12T00:00:00Z",
            lastSeenAt: "2026-05-12T00:00:00Z"
        )
        let merged = original.updated(from: newer)
        // Identity columns come from self (immutable across upserts).
        #expect(merged.identityHash == original.identityHash)
        #expect(merged.templateName == original.templateName)
        #expect(merged.typeName == original.typeName)
    }

    // MARK: - Equality semantics

    @Test("V1.33.A — Equatable conformance is structural (all 11 fields)")
    func equatableIsStructural() {
        let entry1 = Self.exampleEntry
        let entry2 = SemanticIndexEntry(
            identityHash: entry1.identityHash,
            templateName: entry1.templateName,
            typeName: entry1.typeName,
            score: entry1.score,
            tier: entry1.tier,
            primaryFunctionName: entry1.primaryFunctionName,
            location: entry1.location,
            decision: entry1.decision,
            decisionAt: entry1.decisionAt,
            firstSeenAt: entry1.firstSeenAt,
            lastSeenAt: entry1.lastSeenAt
        )
        #expect(entry1 == entry2)
        // Change one field → not equal.
        let entry3 = SemanticIndexEntry(
            identityHash: entry1.identityHash,
            templateName: entry1.templateName,
            typeName: entry1.typeName,
            score: 99,
            tier: entry1.tier,
            primaryFunctionName: entry1.primaryFunctionName,
            location: entry1.location,
            decision: entry1.decision,
            decisionAt: entry1.decisionAt,
            firstSeenAt: entry1.firstSeenAt,
            lastSeenAt: entry1.lastSeenAt
        )
        #expect(entry1 != entry3)
    }

    // MARK: - V1.47.B typeShape field — schema migration

    @Test("V1.47.B — pre-v1.47 JSON (no typeShape) decodes cleanly with nil")
    func v1MigrationDecodesWithoutTypeShape() throws {
        // Verbatim pre-v1.47 entry JSON — no typeShape key.
        let json = """
        {
            "decision": "accept",
            "decisionAt": "2026-05-11T12:34:56Z",
            "firstSeenAt": "2026-05-10T00:00:00Z",
            "identityHash": "0xBC43359C0574816B",
            "lastSeenAt": "2026-05-11T12:34:56Z",
            "location": "/foo/bar/_HashTable+UnsafeHandle.swift:201",
            "primaryFunctionName": "_value(forBucketContents:)",
            "score": 35,
            "templateName": "round-trip",
            "tier": "Possible",
            "typeName": "_HashTable.UnsafeHandle"
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(SemanticIndexEntry.self, from: data)
        #expect(decoded.typeShape == nil)
        // All other fields preserved.
        #expect(decoded.identityHash == "0xBC43359C0574816B")
        #expect(decoded.templateName == "round-trip")
        #expect(decoded.score == 35)
    }

    @Test("V1.47.B — v1.47 JSON with non-nil typeShape round-trips bit-for-bit")
    func v2JsonWithTypeShapeRoundTrips() throws {
        let shape = IndexedTypeShape(
            name: "Foo",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [
                IndexedTypeShape.StoredMember(name: "value", typeName: "Int")
            ],
            hasUserInit: false
        )
        let entry = SemanticIndexEntry(
            identityHash: "0xBC43359C0574816B",
            templateName: "idempotence",
            typeName: "Foo",
            score: 30,
            tier: "Possible",
            primaryFunctionName: "normalize(_:)",
            location: "/a.swift:1",
            decision: nil,
            decisionAt: nil,
            firstSeenAt: "2026-05-12T00:00:00Z",
            lastSeenAt: "2026-05-12T00:00:00Z",
            typeShape: shape
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(SemanticIndexEntry.self, from: data)
        #expect(decoded.typeShape == shape)
        #expect(decoded == entry)
    }

    @Test("V1.47.B — typeShape == nil on encode omits the field (vs. emits null)")
    func nilTypeShapeOmitsFieldOnEncode() throws {
        let entry = SemanticIndexEntry(
            identityHash: "0xBC43359C0574816B",
            templateName: "round-trip",
            typeName: "Complex<Double>",
            score: 30,
            tier: "Possible",
            primaryFunctionName: "exp(_:)",
            location: "/a.swift:1",
            firstSeenAt: "2026-05-12T00:00:00Z",
            lastSeenAt: "2026-05-12T00:00:00Z",
            typeShape: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(entry)
        let jsonString = String(data: data, encoding: .utf8) ?? ""
        // The default JSONEncoder + encodeIfPresent omits nil-Optional keys.
        // Either omitted-key or "typeShape":null would be acceptable on the
        // wire, but encodeIfPresent specifically takes the omitted path.
        #expect(!jsonString.contains("\"typeShape\""))
    }

    @Test("V1.47.B — updated(from:) propagates typeShape from other")
    func updatedPropagatesTypeShape() {
        let original = Self.exampleEntry
        let newShape = IndexedTypeShape(
            name: "_HashTable.UnsafeHandle",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false
        )
        let newer = SemanticIndexEntry(
            identityHash: original.identityHash,
            templateName: original.templateName,
            typeName: original.typeName,
            score: original.score,
            tier: original.tier,
            primaryFunctionName: original.primaryFunctionName,
            location: original.location,
            decision: original.decision,
            decisionAt: original.decisionAt,
            firstSeenAt: original.firstSeenAt,
            lastSeenAt: original.lastSeenAt,
            typeShape: newShape
        )
        let merged = original.updated(from: newer)
        #expect(merged.typeShape == newShape)
    }
}
