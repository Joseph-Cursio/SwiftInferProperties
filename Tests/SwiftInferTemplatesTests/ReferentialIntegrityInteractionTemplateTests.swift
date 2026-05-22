import Foundation
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// V2.0 M6 — ReferentialIntegrityInteractionTemplate tests. Pure:
// given a candidate + witness, assert on the emitted suggestion.

@Suite("ReferentialIntegrityInteractionTemplate — V2.0 M6 suggestion emission")
struct RefIntegrityTemplateTests {

    private func candidate() -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/MyApp/F.swift:1",
            enclosingTypeName: nil,
            functionName: "reduce",
            signatureShape: .stateActionReturnsState,
            stateTypeName: "AppState",
            actionTypeName: "AppAction",
            carrierKind: .elmStyle
        )
    }

    private func witness(
        selected: String = "selectedID",
        selectedType: String = "UUID?",
        collection: String = "items",
        element: String = "Item"
    ) -> ReferentialIntegrityWitness {
        ReferentialIntegrityWitness(
            selectedPropertyName: selected,
            selectedTypeName: selectedType,
            collectionPropertyName: collection,
            elementTypeName: element
        )
    }

    private let firstSeenAt = ISO8601DateFormatter().date(from: "2026-05-15T10:00:00Z")!

    // MARK: - analyze

    @Test("empty witnesses → empty suggestions")
    func emptyWitnesses() {
        let suggestions = ReferentialIntegrityInteractionTemplate.analyze(
            candidate: candidate(),
            witnesses: [],
            firstSeenAt: firstSeenAt
        )
        #expect(suggestions.isEmpty)
    }

    @Test("one witness → one suggestion with family:.referentialIntegrity")
    func oneWitness() {
        let suggestions = ReferentialIntegrityInteractionTemplate.analyze(
            candidate: candidate(),
            witnesses: [witness()],
            firstSeenAt: firstSeenAt
        )
        #expect(suggestions.count == 1)
        #expect(suggestions[0].family == .referentialIntegrity)
    }

    // MARK: - Predicate shape

    @Test("predicate is `state.<sel> == nil || state.<coll>.contains { $0.id == state.<sel> }`")
    func predicateShape() {
        let suggestion = ReferentialIntegrityInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        #expect(suggestion.predicate.contains("state.selectedID == nil"))
        #expect(suggestion.predicate.contains("||"))
        #expect(suggestion.predicate.contains("state.items.contains"))
        #expect(suggestion.predicate.contains("$0.id == state.selectedID"))
    }

    @Test("predicate substitutes the actual selected + collection names")
    func predicateSubstitutesNames() {
        let suggestion = ReferentialIntegrityInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(
                selected: "selectedMessageID",
                collection: "messages",
                element: "Message"
            ),
            firstSeenAt: firstSeenAt
        )
        #expect(suggestion.predicate.contains("state.selectedMessageID"))
        #expect(suggestion.predicate.contains("state.messages.contains"))
        #expect(!suggestion.predicate.contains("selectedID")) // wrong name shouldn't leak
    }

    // MARK: - Score / tier

    @Test("score lands in .possible band (20-39)")
    func scoreInPossibleBand() {
        let suggestion = ReferentialIntegrityInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        #expect(suggestion.score >= 20)
        #expect(suggestion.score < 40)
        #expect(suggestion.tier == .possible)
    }

    // MARK: - Explainability

    @Test("whySuggested names the selected + collection field shapes")
    func whySuggestedExplains() {
        let suggestion = ReferentialIntegrityInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        let combined = suggestion.whySuggested.joined(separator: " | ")
        #expect(combined.contains("selectedID: UUID?"))
        #expect(combined.contains("items: [Item]"))
    }

    @Test("whyMightBeWrong calls out the Identifiable + stale-by-design caveats")
    func whyMightBeWrongCaveats() {
        let suggestion = ReferentialIntegrityInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        let combined = suggestion.whyMightBeWrong.joined(separator: " | ")
        #expect(combined.contains("Identifiable"))
        #expect(combined.contains("stale"))
        #expect(combined.contains("init()"))
    }

    // MARK: - Identity

    @Test("identity is stable for the same (family, reducer, predicate)")
    func identityStability() {
        let first = ReferentialIntegrityInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        let second = ReferentialIntegrityInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        #expect(first.identity == second.identity)
    }

    @Test("identity varies by witness")
    func identityVariesByWitness() {
        let alpha = ReferentialIntegrityInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(selected: "selectedItemID", collection: "items"),
            firstSeenAt: firstSeenAt
        )
        let beta = ReferentialIntegrityInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(selected: "selectedUserID", collection: "users"),
            firstSeenAt: firstSeenAt
        )
        #expect(alpha.identity != beta.identity)
    }
}
