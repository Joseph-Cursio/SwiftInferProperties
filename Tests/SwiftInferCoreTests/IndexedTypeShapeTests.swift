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

    @Test("WS-2 — initializers survive kit→mirror→JSON→kit and enable .initializerBased")
    func initializersRoundTripEnableInitializerBased() throws {
        // A struct whose user `init` suppresses the memberwise one; both params
        // are RawType-resolvable, so Tier 6 initializerBased should apply.
        // Pre-WS-2 the mirror dropped `initializers`, so the persisted shape
        // round-tripped to hasUserInit=true + empty inits → strategist `.todo`.
        let kitShape = TypeShape(
            name: "RuleParams",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: [
                PropertyLawCore.StoredMember(name: "count", typeName: "Int"),
                PropertyLawCore.StoredMember(name: "label", typeName: "String")
            ],
            hasUserInit: true,
            initializers: [
                PropertyLawCore.InitializerSignature(
                    parameters: [
                        PropertyLawCore.InitializerParameter(label: "count", typeName: "Int"),
                        PropertyLawCore.InitializerParameter(label: "label", typeName: "String")
                    ]
                )
            ]
        )
        let mirror = IndexedTypeShape(from: kitShape)
        #expect(mirror.initializers.count == 1)
        #expect(mirror.initializers[0].parameters.map(\.typeName) == ["Int", "String"])

        let data = try Self.canonicalEncoder.encode(mirror)
        let decoded = try JSONDecoder().decode(IndexedTypeShape.self, from: data)
        #expect(decoded.initializers == mirror.initializers)

        let roundTripped = decoded.toKitShape()
        #expect(roundTripped.initializers.count == 1)
        // The payoff: memberwise declines (hasUserInit), and the strategist now
        // derives an init-lift instead of falling through to `.todo`.
        guard case .initializerBased = DerivationStrategist.strategy(for: roundTripped) else {
            Issue.record("expected .initializerBased, got \(DerivationStrategist.strategy(for: roundTripped))")
            return
        }
    }

    @Test("missing initializers field decodes to [] (backward compat)")
    func missingInitializersDecodesEmpty() throws {
        let json = """
        { "name": "Foo", "kind": "struct", "inheritedTypes": [], "hasUserGen": false }
        """
        let decoded = try JSONDecoder().decode(IndexedTypeShape.self, from: Data(json.utf8))
        #expect(decoded.initializers.isEmpty)
    }
}
