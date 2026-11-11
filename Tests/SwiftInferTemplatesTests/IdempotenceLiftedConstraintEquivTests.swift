import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("IdempotenceTemplate (lifted) — V1.39.D Constraint equivalence")
struct IdempotenceLiftedConstraintEquivTests {

    private static let loc = SourceLocation(file: "T.swift", line: 1, column: 1)

    private static func liftedTransformation(
        mutatingFuncName: String,
        carrier: String = "MySet"
    ) throws -> LiftedTransformation {
        let summary = FunctionSummary(
            name: mutatingFuncName,
            parameters: [],
            returnTypeText: "Void",
            isThrows: false, isAsync: false, isMutating: true, isStatic: false,
            location: loc,
            containingTypeName: carrier,
            bodySignals: .empty
        )
        let resolver = CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: carrier,
                kind: .struct,
                inheritedTypes: [],
                location: loc,
                storedMembers: [StoredMember(name: "x", typeName: "Int")]
            ),
        ])
        return try #require(LiftedTransformation.lift(summary, carrierKindResolver: resolver))
    }

    @Test("V1.39.D — Idempotence lifted: wrapper matches Constraint output across corpus")
    func equivalence() throws {
        let resolver = CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: "MySet",
                kind: .struct,
                inheritedTypes: [],
                location: Self.loc,
                storedMembers: [StoredMember(name: "x", typeName: "Int")]
            ),
        ])
        let corpus: [(label: String, lifted: LiftedTransformation)] = [
            ("removeAll", try Self.liftedTransformation(mutatingFuncName: "removeAll")),
            ("sort", try Self.liftedTransformation(mutatingFuncName: "sort")),
            ("normalize", try Self.liftedTransformation(mutatingFuncName: "normalize")),
        ]
        for (label, lifted) in corpus {
            let wrapper = IdempotenceTemplate.suggest(
                forLifted: lifted, carrierKindResolver: resolver
            )
            let runner = ConstraintRunner.suggest(
                constraint: IdempotenceTemplate.makeLiftedConstraint(
                    vocabulary: .empty,
                    inheritedTypesByName: [:],
                    carrierKindResolver: resolver
                ),
                subject: lifted
            )
            #expect(wrapper == runner, "[\(label)] disagree")
        }
    }

    @Test("V1.39.D — Idempotence lifted: lifted.rationale appears in whySuggested between evidence and signals")
    func rationaleInsertedBetweenEvidenceAndSignals() throws {
        let resolver = CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: "MySet",
                kind: .struct,
                inheritedTypes: [],
                location: Self.loc,
                storedMembers: [StoredMember(name: "x", typeName: "Int")]
            ),
        ])
        let lifted = try Self.liftedTransformation(mutatingFuncName: "normalize")
        let suggestion = try #require(IdempotenceTemplate.suggest(
            forLifted: lifted, carrierKindResolver: resolver
        ))
        let lines = suggestion.explainability.whySuggested
        // First line is evidence (display + signature + location)
        #expect(lines[0].contains("normalize"))
        // Second line should be lifted.rationale
        #expect(lines[1] == lifted.rationale)
        // Remaining lines are signal-formatted
        #expect(lines.count >= 3, "expected at least 3 whySuggested lines")
    }
}
