import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("InversePairTemplate+Lifted — V1.40.F Constraint equivalence")
struct InversePairLiftedEquivTests {

    private static let loc = SourceLocation(file: "T.swift", line: 1, column: 1)

    private static func resolver(carrier: String = "MyBag") -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: carrier, kind: .struct, inheritedTypes: [],
                location: loc, storedMembers: [StoredMember(name: "x", typeName: "Int")]
            ),
        ])
    }

    private static func makeLiftedInversePair() throws -> LiftedInversePair? {
        let resolver = resolver()
        let insertSummary = FunctionSummary(
            name: "insert",
            parameters: [Parameter(label: nil, internalName: "x", typeText: "Int", isInout: false)],
            returnTypeText: "Void",
            isThrows: false, isAsync: false, isMutating: true, isStatic: false,
            location: loc, containingTypeName: "MyBag", bodySignals: .empty
        )
        let removeSummary = FunctionSummary(
            name: "remove",
            parameters: [Parameter(label: nil, internalName: "x", typeText: "Int", isInout: false)],
            returnTypeText: "Void",
            isThrows: false, isAsync: false, isMutating: true, isStatic: false,
            location: loc, containingTypeName: "MyBag", bodySignals: .empty
        )
        let forward = try #require(LiftedTransformation.lift(insertSummary, carrierKindResolver: resolver))
        let reverse = try #require(LiftedTransformation.lift(removeSummary, carrierKindResolver: resolver))
        return LiftedInversePair(
            forward: forward,
            reverse: reverse,
            pairName: LiftedInversePair.NamePair(lhs: "insert", rhs: "remove")
        )
    }

    @Test("V1.40.F — InversePair lifted: wrapper matches Constraint output")
    func equivalence() throws {
        let pair = try #require(try Self.makeLiftedInversePair())
        let resolver = Self.resolver()
        let wrapper = InversePairTemplate.suggest(
            forLifted: pair, carrierKindResolver: resolver
        )
        let runner = ConstraintRunner.suggest(
            constraint: InversePairTemplate.makeLiftedConstraint(carrierKindResolver: resolver),
            subject: pair
        )
        #expect(wrapper == runner)
    }
}
