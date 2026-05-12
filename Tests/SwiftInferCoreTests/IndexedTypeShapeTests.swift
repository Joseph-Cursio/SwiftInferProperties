import Foundation
import PropertyLawCore
import Testing

@testable import SwiftInferCore

// V1.47.A — IndexedTypeShape round-trip tests.
//
// Pins the conversion contract (kit's TypeShape ↔ IndexedTypeShape)
// and JSON encode/decode behavior. Backward-compat is the load-
// bearing concern — pre-v1.47 persisted entries must decode cleanly
// when their `typeShape` field is absent (covered by
// SemanticIndexEntryTests.testV1MigrationDecodesWithoutTypeShape).

@Suite("IndexedTypeShape — V1.47.A round-trip + conversion")
struct IndexedTypeShapeTests {

    private static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    @Test("init(from: kitShape) mirrors every field of the kit's TypeShape")
    func mirrorsKitTypeShape() {
        let kitShape = TypeShape(
            name: "Foo",
            kind: .struct,
            inheritedTypes: ["Equatable", "Hashable"],
            hasUserGen: true,
            storedMembers: [
                PropertyLawCore.StoredMember(name: "x", typeName: "Int"),
                PropertyLawCore.StoredMember(name: "y", typeName: "String")
            ],
            hasUserInit: true
        )
        let mirror = IndexedTypeShape(from: kitShape)
        #expect(mirror.name == "Foo")
        #expect(mirror.kind == .struct)
        #expect(mirror.inheritedTypes == ["Equatable", "Hashable"])
        #expect(mirror.hasUserGen == true)
        #expect(mirror.storedMembers.count == 2)
        #expect(mirror.storedMembers[0].name == "x")
        #expect(mirror.storedMembers[0].typeName == "Int")
        #expect(mirror.storedMembers[1].name == "y")
        #expect(mirror.storedMembers[1].typeName == "String")
        #expect(mirror.hasUserInit == true)
    }

    @Test("toKitShape() round-trips back to a structurally identical TypeShape")
    func roundTripToKitShape() {
        let original = TypeShape(
            name: "Bar",
            kind: .enum,
            inheritedTypes: ["CaseIterable"],
            hasUserGen: false
        )
        let mirror = IndexedTypeShape(from: original)
        let reconstructed = mirror.toKitShape()
        #expect(reconstructed == original)
    }

    @Test("all four Kind cases survive the round-trip")
    func allKindsRoundTrip() {
        let kinds: [TypeShape.Kind] = [.struct, .class, .enum, .actor]
        for kind in kinds {
            let original = TypeShape(
                name: "T", kind: kind, inheritedTypes: [], hasUserGen: false
            )
            let mirror = IndexedTypeShape(from: original)
            #expect(mirror.toKitShape().kind == kind)
        }
    }

    @Test("JSON encode + decode round-trips bit-for-bit")
    func jsonRoundTrip() throws {
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
        let data = try Self.canonicalEncoder.encode(shape)
        let decoded = try JSONDecoder().decode(IndexedTypeShape.self, from: data)
        #expect(decoded == shape)
    }

    @Test("decode tolerates missing storedMembers + hasUserInit fields")
    func decodeIfPresentForOptionalFields() throws {
        // Pre-evolution JSON shape — only the v1 fields are present.
        let json = """
        {
            "name": "Foo",
            "kind": "struct",
            "inheritedTypes": ["Equatable"],
            "hasUserGen": false
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(IndexedTypeShape.self, from: data)
        #expect(decoded.name == "Foo")
        #expect(decoded.kind == .struct)
        #expect(decoded.storedMembers.isEmpty)
        #expect(decoded.hasUserInit == false)
    }

    @Test("StoredMember mirror round-trips name + typeName")
    func storedMemberRoundTrips() throws {
        let original = IndexedTypeShape.StoredMember(name: "x", typeName: "Int")
        let data = try Self.canonicalEncoder.encode(original)
        let decoded = try JSONDecoder().decode(
            IndexedTypeShape.StoredMember.self, from: data
        )
        #expect(decoded == original)
    }
}
