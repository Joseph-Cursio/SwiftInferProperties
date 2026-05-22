import Foundation
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// V2.0 M5 — CardinalityInteractionTemplate tests. Pure: given a
// candidate + witness, assert on the emitted suggestion's
// structure.

@Suite("CardinalityInteractionTemplate — V2.0 M5 suggestion emission")
struct CardinalityInteractionTemplateTests {

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

    private func field(
        name: String,
        kind: CardinalityFieldKind = .optionalPresentation
    ) -> CardinalityWitness.Field {
        let indicator: String
        switch kind {
        case .boolFlag: indicator = "state.\(name)"
        case .optionalPresentation: indicator = "state.\(name) != nil"
        }
        return CardinalityWitness.Field(
            propertyName: name,
            indicator: indicator,
            kind: kind
        )
    }

    private func witness(
        fields: [CardinalityWitness.Field]? = nil
    ) -> CardinalityWitness {
        CardinalityWitness(fields: fields ?? [
            field(name: "activeSheet"),
            field(name: "activeAlert")
        ])
    }

    private let firstSeenAt = ISO8601DateFormatter().date(from: "2026-05-15T10:00:00Z")!

    // MARK: - analyze

    @Test("empty witnesses → empty suggestions")
    func emptyWitnesses() {
        let suggestions = CardinalityInteractionTemplate.analyze(
            candidate: candidate(),
            witnesses: [],
            firstSeenAt: firstSeenAt
        )
        #expect(suggestions.isEmpty)
    }

    @Test("one witness → one suggestion with family:.cardinality")
    func oneWitnessOneSuggestion() {
        let suggestions = CardinalityInteractionTemplate.analyze(
            candidate: candidate(),
            witnesses: [witness()],
            firstSeenAt: firstSeenAt
        )
        #expect(suggestions.count == 1)
        #expect(suggestions[0].family == .cardinality)
    }

    // MARK: - Predicate construction

    @Test("predicate sums indicators wrapped in (x ? 1 : 0) and asserts ≤ 1")
    func predicateShape() {
        let suggestion = CardinalityInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        #expect(suggestion.predicate.hasSuffix(" <= 1"))
        #expect(suggestion.predicate.contains("(state.activeSheet != nil ? 1 : 0)"))
        #expect(suggestion.predicate.contains("(state.activeAlert != nil ? 1 : 0)"))
        #expect(suggestion.predicate.contains(" + "))
    }

    @Test("Bool field indicator does not include != nil")
    func boolPredicateShape() {
        let suggestion = CardinalityInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(fields: [
                field(name: "isShowingSheet", kind: .boolFlag),
                field(name: "isPresentingDetail", kind: .boolFlag)
            ]),
            firstSeenAt: firstSeenAt
        )
        #expect(suggestion.predicate.contains("(state.isShowingSheet ? 1 : 0)"))
        #expect(suggestion.predicate.contains("(state.isPresentingDetail ? 1 : 0)"))
        #expect(!suggestion.predicate.contains("isShowingSheet != nil"))
    }

    @Test("mixed Bool + Optional witness emits both indicator shapes")
    func mixedKindsPredicate() {
        let suggestion = CardinalityInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(fields: [
                field(name: "activeSheet"),
                field(name: "isFullScreenPresenting", kind: .boolFlag)
            ]),
            firstSeenAt: firstSeenAt
        )
        #expect(suggestion.predicate.contains("(state.activeSheet != nil ? 1 : 0)"))
        #expect(suggestion.predicate.contains("(state.isFullScreenPresenting ? 1 : 0)"))
    }

    // MARK: - Score / tier

    @Test("score lands in the .possible band (20-39)")
    func scoreInPossibleBand() {
        let suggestion = CardinalityInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        #expect(suggestion.score >= 20)
        #expect(suggestion.score < 40)
        #expect(suggestion.tier == .possible)
    }

    // MARK: - Explainability

    @Test("whySuggested names the field count + lists the field names")
    func whySuggestedExplains() {
        let suggestion = CardinalityInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        let combined = suggestion.whySuggested.joined(separator: " | ")
        #expect(combined.contains("2 presentation-shaped fields"))
        #expect(combined.contains("activeSheet"))
        #expect(combined.contains("activeAlert"))
    }

    @Test("whyMightBeWrong calls out the structural-only + crude-heuristic caveats")
    func whyMightBeWrongCaveats() {
        let suggestion = CardinalityInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        let combined = suggestion.whyMightBeWrong.joined(separator: " | ")
        #expect(combined.contains("structural"))
        #expect(combined.contains("deliberately crude"))
        #expect(combined.contains("init()"))
    }

    // MARK: - Identity

    @Test("identity is stable for the same (family, reducer, predicate)")
    func identityStability() {
        let first = CardinalityInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        let second = CardinalityInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        #expect(first.identity == second.identity)
    }

    @Test("identity varies when field set differs")
    func identityVariesByFields() {
        let alpha = CardinalityInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(fields: [field(name: "activeSheet"), field(name: "activeAlert")]),
            firstSeenAt: firstSeenAt
        )
        let beta = CardinalityInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(fields: [field(name: "popover"), field(name: "fullScreenCover")]),
            firstSeenAt: firstSeenAt
        )
        #expect(alpha.identity != beta.identity)
    }
}
