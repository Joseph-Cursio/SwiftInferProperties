import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Docstring corroboration reaches the LIFTED (mutating-method) idempotence
/// path — where the swift-collections "already X → no-op" contract idioms live
/// (`insert … if not already present`). The corroborator reads the ORIGINAL
/// mutating method's docstring; +15 boosts the lifted candidate.
@Suite("IdempotenceTemplate — lifted-path docstring corroboration")
struct IdempotenceLiftedDocstringTests {

    private func valueSemanticResolver(carrier: String) -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: carrier,
                kind: .struct,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "count", typeName: "Int")]
            )
        ])
    }

    private func mutatingMethod(_ name: String, carrier: String, doc: String?) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [],
            returnTypeText: "Void",
            isThrows: false,
            isAsync: false,
            isMutating: true,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: carrier,
            bodySignals: .empty,
            docComment: doc
        )
    }

    @Test("A documented idempotent mutator is boosted +15 over its undocumented twin")
    func documentedMutatorBoosted() throws {
        let resolver = valueSemanticResolver(carrier: "Ledger")
        let documented = mutatingMethod(
            "seal",
            carrier: "Ledger",
            doc: "Seals the ledger. Calling seal again does nothing if already sealed."
        )
        let plain = mutatingMethod("seal", carrier: "Ledger", doc: nil)

        let documentedLift = try #require(LiftedTransformation.lift(documented, carrierKindResolver: resolver))
        let plainLift = try #require(LiftedTransformation.lift(plain, carrierKindResolver: resolver))

        let documentedSuggestion = try #require(
            IdempotenceTemplate.suggest(forLifted: documentedLift, carrierKindResolver: resolver)
        )
        let plainSuggestion = try #require(
            IdempotenceTemplate.suggest(forLifted: plainLift, carrierKindResolver: resolver)
        )

        #expect(documentedSuggestion.score.total == plainSuggestion.score.total + 15)
        let why = documentedSuggestion.explainability.whySuggested.joined(separator: "\n")
        #expect(why.contains("Docstring corroborates idempotence"))
    }

    @Test("A mutator documented with bare 'has no effect' (index prose) is NOT boosted")
    func trapPhraseNotBoosted() throws {
        let resolver = valueSemanticResolver(carrier: "Ledger")
        let trap = mutatingMethod(
            "seal",
            carrier: "Ledger",
            doc: "Seals the ledger. A limit greater than the count has no effect."
        )
        let plain = mutatingMethod("seal", carrier: "Ledger", doc: nil)

        let trapLift = try #require(LiftedTransformation.lift(trap, carrierKindResolver: resolver))
        let plainLift = try #require(LiftedTransformation.lift(plain, carrierKindResolver: resolver))

        let trapSuggestion = try #require(
            IdempotenceTemplate.suggest(forLifted: trapLift, carrierKindResolver: resolver)
        )
        let plainSuggestion = try #require(
            IdempotenceTemplate.suggest(forLifted: plainLift, carrierKindResolver: resolver)
        )
        #expect(trapSuggestion.score.total == plainSuggestion.score.total)
    }
}
