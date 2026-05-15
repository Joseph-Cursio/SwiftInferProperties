import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferTemplates

// V2.0 M4.B — ConservationInteractionTemplate tests. Pure: given a
// candidate + witness, assert on the emitted
// InteractionInvariantSuggestion's structure.

@Suite("ConservationInteractionTemplate — V2.0 M4.B suggestion emission")
struct ConservationInteractionTemplateTests {

    private func candidate(
        functionName: String = "reduce",
        enclosingTypeName: String? = nil,
        stateTypeName: String = "AppState",
        actionTypeName: String = "AppAction",
        signatureShape: ReducerSignatureShape = .stateActionReturnsState
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/MyApp/F.swift:1",
            enclosingTypeName: enclosingTypeName,
            functionName: functionName,
            signatureShape: signatureShape,
            stateTypeName: stateTypeName,
            actionTypeName: actionTypeName,
            carrierKind: enclosingTypeName == nil ? .elmStyle : .generic
        )
    }

    private func witness(
        aggregate: String = "count",
        aggregateType: String = "Int",
        collection: String = "items",
        element: String = "String"
    ) -> ConservationWitness {
        ConservationWitness(
            aggregatePropertyName: aggregate,
            aggregateTypeName: aggregateType,
            collectionPropertyName: collection,
            elementTypeName: element
        )
    }

    private let firstSeenAt = ISO8601DateFormatter().date(from: "2026-05-15T10:00:00Z")!

    // MARK: - analyze

    @Test("empty witnesses → empty suggestions")
    func emptyWitnesses() {
        let suggestions = ConservationInteractionTemplate.analyze(
            candidate: candidate(),
            witnesses: [],
            firstSeenAt: firstSeenAt
        )
        #expect(suggestions.isEmpty)
    }

    @Test("one witness → one suggestion with predicate state.<agg> == state.<col>.count")
    func oneWitnessOneSuggestion() {
        let suggestions = ConservationInteractionTemplate.analyze(
            candidate: candidate(),
            witnesses: [witness()],
            firstSeenAt: firstSeenAt
        )
        #expect(suggestions.count == 1)
        let suggestion = suggestions[0]
        #expect(suggestion.family == .conservation)
        #expect(suggestion.predicate == "state.count == state.items.count")
        #expect(suggestion.reducerQualifiedName == "reduce")
    }

    @Test("multiple witnesses → multiple suggestions, one per witness")
    func multipleWitnessesMultipleSuggestions() {
        let suggestions = ConservationInteractionTemplate.analyze(
            candidate: candidate(),
            witnesses: [
                witness(aggregate: "itemCount", collection: "items"),
                witness(aggregate: "tagCount", collection: "tags", element: "Tag")
            ],
            firstSeenAt: firstSeenAt
        )
        #expect(suggestions.count == 2)
        #expect(suggestions[0].predicate == "state.itemCount == state.items.count")
        #expect(suggestions[1].predicate == "state.tagCount == state.tags.count")
    }

    // MARK: - Suggestion shape

    @Test("score lands inside the .possible band (20-39)")
    func scoreInPossibleBand() {
        let suggestion = ConservationInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        #expect(suggestion.score >= 20)
        #expect(suggestion.score < 40)
        #expect(suggestion.tier == .possible)
    }

    @Test("score equals the documented initial weight")
    func scoreEqualsInitialWeight() {
        let suggestion = ConservationInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        #expect(suggestion.score == ConservationInteractionTemplate.initialScore)
    }

    @Test("whySuggested mentions the structural witness + reducer signature")
    func whySuggestedExplains() {
        let suggestion = ConservationInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        #expect(suggestion.whySuggested.count >= 2)
        let combined = suggestion.whySuggested.joined(separator: " | ")
        #expect(combined.contains("count: Int"))
        #expect(combined.contains("items: [String]"))
        #expect(combined.contains("state-action-returns-state"))
    }

    @Test("whyMightBeWrong calls out the M4.B detection limitations")
    func whyMightBeWrongEnumeratesCaveats() {
        let suggestion = ConservationInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        let combined = suggestion.whyMightBeWrong.joined(separator: " | ")
        // The three documented caveats: structural-only detection,
        // count-only predicate (sum/total deferred), initial-state
        // mismatch risk.
        #expect(combined.contains("Action enum + reducer body"))
        #expect(combined.contains("count-shaped"))
        #expect(combined.contains("init()"))
    }

    @Test("identity hash is stable for the same (family, reducer, predicate)")
    func identityStability() {
        let first = ConservationInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        let second = ConservationInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        #expect(first.identity == second.identity)
    }

    @Test("identity hash varies with the witness's aggregate / collection names")
    func identityVariesWithWitness() {
        let alpha = ConservationInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(aggregate: "count", collection: "items"),
            firstSeenAt: firstSeenAt
        )
        let beta = ConservationInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(aggregate: "tagCount", collection: "tags"),
            firstSeenAt: firstSeenAt
        )
        #expect(alpha.identity != beta.identity)
    }
}
