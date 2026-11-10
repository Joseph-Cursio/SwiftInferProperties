import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("DualStyleConsistencyTemplate — V1.38.D Constraint equivalence")
struct DualStyleConsistencyEquivTests {

    private static let location = SourceLocation(file: "T.swift", line: 1, column: 1)

    private static func makePair(
        mutatingName: String,
        nonMutatingName: String
    ) -> DualStylePair {
        let mut = FunctionSummary(
            name: mutatingName,
            parameters: [
                Parameter(label: nil, internalName: "other", typeText: "Self", isInout: false)
            ],
            returnTypeText: "Void",
            isThrows: false, isAsync: false, isMutating: true, isStatic: false,
            location: location,
            containingTypeName: "MySet",
            bodySignals: .empty
        )
        let nonMut = FunctionSummary(
            name: nonMutatingName,
            parameters: [
                Parameter(label: nil, internalName: "other", typeText: "Self", isInout: false)
            ],
            returnTypeText: "Self",
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: location,
            containingTypeName: "MySet",
            bodySignals: .empty
        )
        return DualStylePair(mutatingMember: mut, nonMutatingMember: nonMut, rule: .formPrefixToBare)
    }

    @Test("V1.38.D — DualStyleConsistency: wrapper matches Constraint output across corpus")
    func equivalence() {
        let corpus: [(label: String, pair: DualStylePair)] = [
            ("formUnion_union", Self.makePair(mutatingName: "formUnion", nonMutatingName: "union")),
            ("subtract_subtracting", Self.makePair(mutatingName: "subtract", nonMutatingName: "subtracting")),
            (
                "formIntersection_intersection",
                Self.makePair(mutatingName: "formIntersection", nonMutatingName: "intersection")
            ),
        ]
        for (label, pair) in corpus {
            let wrapper = DualStyleConsistencyTemplate.suggest(for: pair, carrierKindResolver: nil)
            let runner = ConstraintRunner.suggest(
                constraint: DualStyleConsistencyTemplate.makeConstraint(carrierKindResolver: nil),
                subject: pair
            )
            #expect(wrapper == runner, "[\(label)] disagree")
        }
    }

    @Test("V1.38.D — DualStyleConsistency: 2 constant caveats")
    func caveatsConstant() throws {
        let suggestion = try #require(
            DualStyleConsistencyTemplate.suggest(
                for: Self.makePair(mutatingName: "formUnion", nonMutatingName: "union")
            )
        )
        #expect(suggestion.explainability.whyMightBeWrong.count == 2)
    }
}
