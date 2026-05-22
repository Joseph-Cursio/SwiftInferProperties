import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// V1.39.D — equivalence tests for the v1.39 batch migration of
/// RoundTrip + Idempotence (non-lifted + lifted) to the Constraint
/// Engine (PRD §20.2). Each suite asserts wrapper-output == direct-
/// Constraint-output across a fixture corpus.

@Suite("RoundTripTemplate — V1.39.D Constraint equivalence")
struct RoundTripConstraintEquivalenceTests {

    private static let loc = SourceLocation(file: "T.swift", line: 1, column: 1)

    private static func summary(
        name: String,
        param: String,
        ret: String,
        container: String? = "Foo"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "x", typeText: param, isInout: false)],
            returnTypeText: ret,
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: loc,
            containingTypeName: container,
            bodySignals: .empty
        )
    }

    @Test("V1.39.D — RoundTrip: wrapper matches Constraint output across corpus")
    func equivalence() {
        let corpus: [(label: String, pair: FunctionPair)] = [
            ("encode_decode_str_int", FunctionPair(
                forward: Self.summary(name: "encode", param: "Int", ret: "String"),
                reverse: Self.summary(name: "decode", param: "String", ret: "Int")
            )),
            ("parse_format", FunctionPair(
                forward: Self.summary(name: "parse", param: "String", ret: "MyToken"),
                reverse: Self.summary(name: "format", param: "MyToken", ret: "String")
            )),
            ("cross_type", FunctionPair(
                forward: Self.summary(name: "to", param: "A", ret: "B", container: "ContainerA"),
                reverse: Self.summary(name: "from", param: "B", ret: "A", container: "ContainerB")
            ))
        ]
        for (label, pair) in corpus {
            let wrapper = RoundTripTemplate.suggest(for: pair)
            let runner = ConstraintRunner.suggest(
                constraint: RoundTripTemplate.makeConstraint(
                    vocabulary: .empty,
                    inheritedTypesByName: [:],
                    carrierKindResolver: nil
                ),
                subject: pair
            )
            #expect(wrapper == runner, "[\(label)] disagree")
        }
    }

    @Test("V1.39.D — RoundTrip: caveats are 2 constant entries")
    func caveats() throws {
        let pair = FunctionPair(
            forward: Self.summary(name: "encode", param: "Int", ret: "String"),
            reverse: Self.summary(name: "decode", param: "String", ret: "Int")
        )
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair))
        #expect(suggestion.explainability.whyMightBeWrong.count == 2)
    }
}

@Suite("IdempotenceTemplate (non-lifted) — V1.39.D Constraint equivalence")
struct IdempotenceConstraintEquivalenceTests {

    private static let loc = SourceLocation(file: "T.swift", line: 1, column: 1)

    private static func summary(
        name: String,
        type: String = "Foo"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "x", typeText: type, isInout: false)],
            returnTypeText: type,
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: loc,
            containingTypeName: type,
            bodySignals: .empty
        )
    }

    @Test("V1.39.D — Idempotence non-lifted: wrapper matches Constraint output across corpus")
    func equivalence() {
        let corpus: [(label: String, summary: FunctionSummary)] = [
            ("curated_normalize", Self.summary(name: "normalize")),
            ("bare_someOp", Self.summary(name: "someOp")),
            ("math_log", Self.summary(name: "log", type: "Double"))
        ]
        for (label, summary) in corpus {
            let wrapper = IdempotenceTemplate.suggest(for: summary)
            let runner = ConstraintRunner.suggest(
                constraint: IdempotenceTemplate.makeConstraint(
                    vocabulary: .empty,
                    inheritedTypesByName: [:],
                    carrierKindResolver: nil
                ),
                subject: summary
            )
            #expect(wrapper == runner, "[\(label)] disagree")
        }
    }
}

@Suite("IdempotenceTemplate (lifted) — V1.39.D Constraint equivalence")
struct IdempotenceLiftedConstraintEquivTests {

    private static let loc = SourceLocation(file: "T.swift", line: 1, column: 1)

    private static func liftedTransformation(
        mutatingFuncName: String,
        carrier: String = "MySet"
    ) -> LiftedTransformation {
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
            )
        ])
        return LiftedTransformation.lift(summary, carrierKindResolver: resolver)!
    }

    @Test("V1.39.D — Idempotence lifted: wrapper matches Constraint output across corpus")
    func equivalence() {
        let resolver = CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: "MySet",
                kind: .struct,
                inheritedTypes: [],
                location: Self.loc,
                storedMembers: [StoredMember(name: "x", typeName: "Int")]
            )
        ])
        let corpus: [(label: String, lifted: LiftedTransformation)] = [
            ("removeAll", Self.liftedTransformation(mutatingFuncName: "removeAll")),
            ("sort", Self.liftedTransformation(mutatingFuncName: "sort")),
            ("normalize", Self.liftedTransformation(mutatingFuncName: "normalize"))
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
            )
        ])
        let lifted = Self.liftedTransformation(mutatingFuncName: "normalize")
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
