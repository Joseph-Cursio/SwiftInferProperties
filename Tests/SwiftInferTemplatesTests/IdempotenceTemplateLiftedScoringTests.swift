import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("IdempotenceTemplate — V1.19.B lift score signals + identity + explainability")
struct IdempotenceTemplateLiftedScoringTests {

    // MARK: - Helpers

    private func valueSemanticResolver(carrier: String = "Bag") -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: carrier,
                kind: .struct,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "items", typeName: "[Int]")]
            )
        ])
    }

    private func mutator(
        _ name: String,
        params: [Parameter] = [],
        carrier: String = "Bag",
        bodySignals: BodySignals = .empty
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: params,
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

    private func liftedNoParam(
        _ name: String = "removeAll",
        carrier: String = "Bag"
    ) -> LiftedTransformation {
        LiftedTransformation.lift(
            mutator(name, carrier: carrier),
            carrierKindResolver: valueSemanticResolver(carrier: carrier)
        )!
    }

    private func liftedParamMatchesCarrier(
        _ name: String = "formUnion",
        carrier: String = "Bag"
    ) -> LiftedTransformation {
        LiftedTransformation.lift(
            mutator(
                name,
                params: [Parameter(label: nil, internalName: "p0", typeText: carrier, isInout: false)],
                carrier: carrier
            ),
            carrierKindResolver: valueSemanticResolver(carrier: carrier)
        )!
    }

    // MARK: - Score signals

    @Test("Curated-verb mutating method (`mutating func normalize()`) earns +40 name signal")
    func curatedVerbBoost() throws {
        let suggestion = try #require(IdempotenceTemplate.suggest(
            forLifted: liftedNoParam("normalize"),
            carrierKindResolver: valueSemanticResolver()
        ))
        // 30 type + 40 curated + 5 carrier + 10 lifted = 85 → Strong.
        #expect(suggestion.score.total == 85)
        #expect(suggestion.score.tier == .strong)
    }

    @Test("Project-vocabulary verb earns the same +40 boost")
    func projectVocabularyVerbBoost() throws {
        let vocab = Vocabulary(idempotenceVerbs: ["sanitizeXML"])
        let suggestion = try #require(IdempotenceTemplate.suggest(
            forLifted: liftedNoParam("sanitizeXML"),
            vocabulary: vocab,
            carrierKindResolver: valueSemanticResolver()
        ))
        #expect(suggestion.score.total == 85)
    }

    @Test("liftedFromMutation signal renders +10 with the original method name")
    func liftedFromMutationDetailRenders() throws {
        let suggestion = try #require(IdempotenceTemplate.suggest(
            forLifted: liftedNoParam("removeAll"),
            carrierKindResolver: valueSemanticResolver()
        ))
        let signal = try #require(suggestion.score.signals.first {
            $0.kind == .liftedFromMutation
        })
        #expect(signal.weight == 10)
        #expect(signal.detail.contains("Bag.removeAll"))
        #expect(signal.detail.contains("mutating func"))
    }

    @Test("Value-semantic carrier signal fires (always, by admission gate)")
    func valueSemanticCarrierSignalFires() throws {
        let suggestion = try #require(IdempotenceTemplate.suggest(
            forLifted: liftedNoParam("removeAll"),
            carrierKindResolver: valueSemanticResolver()
        ))
        #expect(suggestion.score.signals.contains { $0.kind == .valueSemanticCarrier })
    }

    @Test("Type-symmetry detail line for no-param lift names the carrier explicitly")
    func noParamTypeSymmetryDetail() throws {
        let suggestion = try #require(IdempotenceTemplate.suggest(
            forLifted: liftedNoParam("removeAll"),
            carrierKindResolver: valueSemanticResolver()
        ))
        let signal = try #require(suggestion.score.signals.first {
            $0.kind == .typeSymmetrySignature
        })
        #expect(signal.detail.contains("(Bag) -> Bag"))
        #expect(signal.detail.contains("no-param mutating"))
    }

    @Test("Type-symmetry detail line for x-curried lift names the binary shape")
    func xCurriedTypeSymmetryDetail() throws {
        let suggestion = try #require(IdempotenceTemplate.suggest(
            forLifted: liftedParamMatchesCarrier("formUnion"),
            carrierKindResolver: valueSemanticResolver()
        ))
        let signal = try #require(suggestion.score.signals.first {
            $0.kind == .typeSymmetrySignature
        })
        #expect(signal.detail.contains("(Bag, Bag) -> Bag"))
        #expect(signal.detail.contains("x-curried"))
    }

    // MARK: - Vetoes

    @Test("Non-deterministic body in original mutating method vetoes")
    func nonDeterministicVetoes() {
        let resolver = valueSemanticResolver()
        let summaryWithVeto = mutator(
            "removeAll",
            bodySignals: BodySignals(
                hasNonDeterministicCall: true,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: ["Date.init"]
            )
        )
        let lifted = LiftedTransformation.lift(summaryWithVeto, carrierKindResolver: resolver)!
        #expect(IdempotenceTemplate.suggest(
            forLifted: lifted,
            carrierKindResolver: resolver
        ) == nil)
    }

    @Test("SetAlgebra-conforming carrier with formUnion lift is vetoed by protocol coverage")
    func setAlgebraCarrierVetoes() {
        let setAlgebraDecl = TypeDecl(
            name: "Bag",
            kind: .struct,
            inheritedTypes: ["SetAlgebra"],
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            storedMembers: [StoredMember(name: "items", typeName: "[Int]")]
        )
        let resolver = CarrierKindResolver(typeDecls: [setAlgebraDecl])
        let inheritedTypesByName = ProtocolCoverageMap.inheritedTypesIndex(from: [setAlgebraDecl])
        let lifted = LiftedTransformation.lift(
            mutator(
                "formUnion",
                params: [Parameter(label: nil, internalName: "p0", typeText: "Bag", isInout: false)]
            ),
            carrierKindResolver: resolver
        )!
        // SetAlgebra-shape veto fires because `formUnion` is in
        // SetAlgebraShape.binaryOps + carrier conforms to SetAlgebra.
        #expect(IdempotenceTemplate.suggest(
            forLifted: lifted,
            inheritedTypesByName: inheritedTypesByName,
            carrierKindResolver: resolver
        ) == nil)
    }

    // MARK: - Identity

    @Test("Identity hash uses `idempotence-lifted|` prefix")
    func identityHasLiftedPrefix() throws {
        let suggestion = try #require(IdempotenceTemplate.suggest(
            forLifted: liftedNoParam("removeAll"),
            carrierKindResolver: valueSemanticResolver()
        ))
        #expect(suggestion.identity.canonicalInput.hasPrefix("idempotence-lifted|"))
    }

    @Test("Cross-validation key uses 'idempotence' template name + the original callee name")
    func crossValidationKeyMatchesTemplate() throws {
        let suggestion = try #require(IdempotenceTemplate.suggest(
            forLifted: liftedNoParam("removeAll"),
            carrierKindResolver: valueSemanticResolver()
        ))
        let key = suggestion.crossValidationKey
        #expect(key.templateName == "idempotence")
        #expect(key.calleeNames == ["Bag.removeAll"])
    }

    // MARK: - Explainability

    @Test("Explainability block carries the lift rationale + value-semantic caveat")
    func explainabilityCarriesRationaleAndCaveat() throws {
        let suggestion = try #require(IdempotenceTemplate.suggest(
            forLifted: liftedNoParam("removeAll"),
            carrierKindResolver: valueSemanticResolver()
        ))
        let why = suggestion.explainability.whySuggested.joined(separator: "\n")
        #expect(why.contains("Lifted from `mutating func Bag.removeAll"))
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("value semantics"))
        #expect(caveats.contains("Bag"))
    }
}
