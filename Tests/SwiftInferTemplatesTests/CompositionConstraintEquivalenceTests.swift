import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("CompositionTemplate — V1.40.F Constraint equivalence")
struct CompositionConstraintEquivalenceTests {

    private static let loc = SourceLocation(file: "T.swift", line: 1, column: 1)

    @Test("V1.40.F — Composition: wrapper matches Constraint output")
    func equivalence() throws {
        let resolver = CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: "Counter", kind: .struct, inheritedTypes: [],
                location: Self.loc, storedMembers: [StoredMember(name: "value", typeName: "Int")]
            ),
        ])
        let summary = FunctionSummary(
            name: "increment",
            parameters: [Parameter(label: "by", internalName: "amount", typeText: "Int", isInout: false)],
            returnTypeText: "Void",
            isThrows: false, isAsync: false, isMutating: true, isStatic: false,
            location: Self.loc, containingTypeName: "Counter", bodySignals: .empty
        )
        let lifted = try #require(LiftedTransformation.lift(summary, carrierKindResolver: resolver))
        let wrapper = CompositionTemplate.suggest(forLifted: lifted, carrierKindResolver: resolver)
        let runner = ConstraintRunner.suggest(
            constraint: CompositionTemplate.makeConstraint(
                vocabulary: .empty, carrierKindResolver: resolver
            ),
            subject: lifted
        )
        #expect(wrapper == runner)
    }
}
