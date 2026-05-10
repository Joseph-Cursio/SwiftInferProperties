import PropertyLawCore
import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("CompositionTemplate — V1.19.C additive-monoid mutating composition")
struct CompositionTemplateTests {

    // MARK: - Helpers

    private func valueSemanticResolver(carrier: String = "Counter") -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: carrier,
                kind: .struct,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "value", typeName: "Int")]
            )
        ])
    }

    private func mutator(
        _ name: String,
        paramType: String = "Int",
        paramLabel: String? = "by",
        carrier: String = "Counter",
        bodySignals: BodySignals = .empty
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(
                    label: paramLabel,
                    internalName: "amount",
                    typeText: paramType,
                    isInout: false
                )
            ],
            returnTypeText: "Void",
            isThrows: false,
            isAsync: false,
            isMutating: true,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: carrier,
            bodySignals: bodySignals
        )
    }

    private func lifted(
        _ name: String = "increment",
        paramType: String = "Int",
        carrier: String = "Counter",
        bodySignals: BodySignals = .empty
    ) -> LiftedTransformation {
        LiftedTransformation.lift(
            mutator(name, paramType: paramType, carrier: carrier, bodySignals: bodySignals),
            carrierKindResolver: valueSemanticResolver(carrier: carrier)
        )!
    }

    // MARK: - Admission

    @Test("Canonical increment(by: Int) earns Strong baseline (30+40+5+10=85)")
    func canonicalIncrementIsStrong() throws {
        let suggestion = try #require(CompositionTemplate.suggest(
            forLifted: lifted(),
            carrierKindResolver: valueSemanticResolver()
        ))
        #expect(suggestion.score.total == 85)
        #expect(suggestion.score.tier == .strong)
        #expect(suggestion.templateName == "composition")
    }

    @Test("Project-vocabulary verb earns the same +40 boost")
    func projectVocabularyVerbBoost() throws {
        let vocab = Vocabulary(compositionVerbs: ["nudge"])
        let suggestion = try #require(CompositionTemplate.suggest(
            forLifted: lifted("nudge"),
            vocabulary: vocab,
            carrierKindResolver: valueSemanticResolver()
        ))
        #expect(suggestion.score.total == 85)
    }

    @Test("Param type not in curated additive-monoid set is rejected")
    func nonAdditiveParamRejected() {
        // String isn't AdditiveArithmetic in the curated set.
        let lift = lifted(paramType: "String")
        #expect(CompositionTemplate.suggest(
            forLifted: lift,
            carrierKindResolver: valueSemanticResolver()
        ) == nil)
    }

    @Test("Param type matching carrier is rejected (Idempotence x-curried path)")
    func paramMatchesCarrierRejected() {
        // mutating func formUnion(_:Counter) — flows through IdempotenceTemplate.
        let lift = lifted(paramType: "Counter")
        #expect(CompositionTemplate.suggest(
            forLifted: lift,
            carrierKindResolver: valueSemanticResolver()
        ) == nil)
    }

    @Test("No-param mutator is rejected (Idempotence no-param path)")
    func noParamRejected() {
        let resolver = valueSemanticResolver()
        let summaryNoParam = FunctionSummary(
            name: "increment",
            parameters: [],
            returnTypeText: "Void",
            isThrows: false,
            isAsync: false,
            isMutating: true,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: "Counter",
            bodySignals: .empty
        )
        let lift = LiftedTransformation.lift(summaryNoParam, carrierKindResolver: resolver)!
        #expect(CompositionTemplate.suggest(
            forLifted: lift,
            carrierKindResolver: resolver
        ) == nil)
    }

    @Test("Non-curated method name is rejected (no naming signal → no suggestion)")
    func nonCuratedNameRejected() {
        // Type-shape matches but the name 'munge' isn't in the curated
        // verb list and the project vocabulary is empty — no suggestion.
        #expect(CompositionTemplate.suggest(
            forLifted: lifted("munge"),
            carrierKindResolver: valueSemanticResolver()
        ) == nil)
    }

    @Test("Inout parameter disqualifies (aliasing breaks the lift)")
    func inoutParamRejected() {
        let resolver = valueSemanticResolver()
        let summaryInout = FunctionSummary(
            name: "increment",
            parameters: [
                Parameter(label: "by", internalName: "amount", typeText: "Int", isInout: true)
            ],
            returnTypeText: "Void",
            isThrows: false,
            isAsync: false,
            isMutating: true,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: "Counter",
            bodySignals: .empty
        )
        let lift = LiftedTransformation.lift(summaryInout, carrierKindResolver: resolver)!
        #expect(CompositionTemplate.suggest(
            forLifted: lift,
            carrierKindResolver: resolver
        ) == nil)
    }

    // MARK: - Curated additive-monoid types coverage

    @Test("Each curated additive-monoid type admits the composition shape")
    func allCuratedTypesAdmit() throws {
        for typeText in CompositionTemplate.curatedAdditiveTypes {
            let suggestion = try #require(CompositionTemplate.suggest(
                forLifted: lifted(paramType: typeText),
                carrierKindResolver: valueSemanticResolver()
            ), "expected \(typeText) to admit composition shape")
            #expect(suggestion.score.total == 85)
        }
    }

    @Test("Generic specialization strips for matching (Counter<Element> → Counter)")
    func genericSpecializationStrips() throws {
        let suggestion = try #require(CompositionTemplate.suggest(
            forLifted: lifted(paramType: "Int<NotRealButTested>"),
            carrierKindResolver: valueSemanticResolver()
        ))
        // Stripped to "Int" → matches curated set.
        #expect(suggestion.score.total == 85)
    }

    // MARK: - Vetoes

    @Test("Non-deterministic body in original mutating method vetoes")
    func nonDeterministicVetoes() {
        let lift = lifted(bodySignals: BodySignals(
            hasNonDeterministicCall: true,
            hasSelfComposition: false,
            nonDeterministicAPIsDetected: ["Date.init"]
        ))
        #expect(CompositionTemplate.suggest(
            forLifted: lift,
            carrierKindResolver: valueSemanticResolver()
        ) == nil)
    }

    // MARK: - Identity

    @Test("Identity uses `composition|` prefix")
    func identityPrefix() throws {
        let suggestion = try #require(CompositionTemplate.suggest(
            forLifted: lifted(),
            carrierKindResolver: valueSemanticResolver()
        ))
        #expect(suggestion.identity.canonicalInput.hasPrefix("composition|"))
    }

    @Test("Cross-validation key uses 'composition' template name")
    func crossValidationKey() throws {
        let suggestion = try #require(CompositionTemplate.suggest(
            forLifted: lifted(),
            carrierKindResolver: valueSemanticResolver()
        ))
        let key = suggestion.crossValidationKey
        #expect(key.templateName == "composition")
        #expect(key.calleeNames == ["Counter.increment"])
    }
}
