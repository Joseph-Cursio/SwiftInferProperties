import PropertyLawCore
import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

/// V1.24.C — non-deterministic mutator-name veto on idempotence-lifted.
/// Direct cycle-20 finding closure (V1.20.C #40 unknown verdict on
/// `OrderedDictionary.shuffle()` lifted-idempotence; surfaced despite
/// being non-deterministic because the existing body-signal detector
/// missed the OC RNG pattern).
@Suite("IdempotenceTemplate — V1.24.C non-deterministic mutator veto")
struct IdempotenceTemplateNonDeterministicMutatorTests {

    private func summary(
        _ name: String,
        carrier: String = "OrderedDictionary"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [],
            returnTypeText: "Void",
            isThrows: false, isAsync: false, isMutating: true, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    private func valueSemanticResolver(carrier: String = "OrderedDictionary") -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: carrier,
                kind: .struct,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "elements", typeName: "[Int]")]
            )
        ])
    }

    private func lifted(method: String, carrier: String = "OrderedDictionary") -> LiftedTransformation {
        LiftedTransformation.lift(
            summary(method, carrier: carrier),
            carrierKindResolver: valueSemanticResolver(carrier: carrier)
        )!
    }

    // MARK: - Curated set membership

    @Test("NonDeterministicMutatorNames.curated contains 'shuffle' (cycle-20 case)")
    func curatedContainsShuffle() {
        #expect(NonDeterministicMutatorNames.curated.contains("shuffle"))
    }

    // MARK: - Veto fires on 'shuffle'

    @Test("'shuffle' on OrderedDictionary fires veto (cycle-20 #40 case)")
    func shuffleOnOrderedDictionaryVetoes() {
        let signal = IdempotenceTemplate.nonDeterministicMutatorVeto(forLifted: lifted(method: "shuffle"))
        let veto = try! #require(signal)
        #expect(veto.isVeto)
        #expect(veto.kind == .nonDeterministicBody)
        #expect(veto.detail.contains("'shuffle'"))
        #expect(veto.detail.contains("RNG-driven"))
    }

    @Test("'shuffle' fires veto on any value-semantic carrier (OrderedSet, Array, etc.)")
    func shuffleVetoesAnyCarrier() {
        for carrier in ["OrderedSet", "Array", "OrderedDictionary.Elements"] {
            let signal = IdempotenceTemplate.nonDeterministicMutatorVeto(
                forLifted: lifted(method: "shuffle", carrier: carrier)
            )
            #expect(signal?.isVeto == true, "shuffle should veto on '\(carrier)'")
        }
    }

    // MARK: - Veto does NOT fire on non-curated names

    @Test("'sort' does NOT fire non-deterministic veto (sort is deterministic + idempotent)")
    func sortDoesNotVeto() {
        let signal = IdempotenceTemplate.nonDeterministicMutatorVeto(forLifted: lifted(method: "sort"))
        #expect(signal == nil)
    }

    @Test("Non-curated names ('reverse', 'normalize', etc.) do not fire this veto")
    func nonCuratedDoesNotVeto() {
        for name in ["reverse", "normalize", "randomElement", "permute"] {
            let signal = IdempotenceTemplate.nonDeterministicMutatorVeto(forLifted: lifted(method: name))
            #expect(signal == nil, "'\(name)' should not fire non-deterministic mutator veto at v1.24")
        }
    }

    // MARK: - End-to-end suggest()

    @Test("End-to-end: OrderedDictionary.shuffle() lifted-idempotence is suppressed at v1.24.C")
    func endToEndShuffleSuppressed() {
        let suggestion = IdempotenceTemplate.suggest(
            forLifted: lifted(method: "shuffle"),
            carrierKindResolver: valueSemanticResolver()
        )
        #expect(suggestion == nil, "V1.24.C should suppress shuffle lifted-idempotence")
    }
}
