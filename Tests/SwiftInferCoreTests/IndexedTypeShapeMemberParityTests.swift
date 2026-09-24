import Foundation
import PropertyLawCore
import PropertyLawKit
@testable import SwiftInferCore
import Testing

/// `IndexedTypeShape` round-trips stored members **with their access level**.
///
/// The parity law in `IndexedTypeShapeParityPropertyTests` draws `storedMembers: []` on every
/// trial, so it compared `[] == []` and could not see a dropped member field. That is how
/// `accessLevel` was lost in the mirror: a `private` member read back as the implicit level, and
/// the kit then emitted a memberwise call no test file can make. This draws members at every
/// access level, and was watched failing against the mirror before the field existed.
@Suite("IndexedTypeShape — stored members keep their access level")
struct IndexedTypeShapeMemberParityTests {

    private static let typeSpellings = ["String", "Int", "[String]", "Set<Int>"]

    private static let memberGen = zip(
        Gen<Int>.int(in: 0...5),
        Gen.element(of: PropertyLawCore.AccessLevel.allCases).map { $0! }
    ).map { index, access in
        PropertyLawCore.StoredMember(
            name: "member\(index)",
            typeName: Self.typeSpellings[index % Self.typeSpellings.count],
            accessLevel: access
        )
    }

    private static let shapeGen = memberGen.array(of: 1...4).map { members in
        TypeShape(
            name: "Session",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: members
        )
    }

    @Test("stored members survive the mirror, access level included")
    func membersRoundTrip() async {
        await propertyCheck(input: Self.shapeGen) { shape in
            let restored = IndexedTypeShape(from: shape).toKitShape()
            #expect(restored.storedMembers == shape.storedMembers)
        }
    }

    /// An index written before the field existed has no `accessLevel` key; it must still decode,
    /// and read as the implicit level rather than as some other one.
    @Test("an index without the field decodes as the implicit level")
    func legacyMemberDecodes() throws {
        let json = Data(#"{"name":"received","typeName":"Set<Int>"}"#.utf8)
        let member = try JSONDecoder().decode(IndexedTypeShape.StoredMember.self, from: json)
        #expect(member.accessLevel == nil)
        let shape = IndexedTypeShape(
            name: "Session", kind: .struct, inheritedTypes: [], hasUserGen: false, storedMembers: [member]
        )
        #expect(shape.toKitShape().storedMembers.first?.accessLevel == .implicit)
    }
}
