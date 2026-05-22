import Foundation
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// V2.0 M7 — BiconditionalInteractionTemplate tests. Pure: given a
// candidate + witness, assert on the emitted suggestion.

@Suite("BiconditionalInteractionTemplate — V2.0 M7 suggestion emission")
struct BiconditionalTemplateTests {

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
        bool: String = "isLoading",
        boolType: String = "Bool",
        optional: String = "activeTask",
        optionalType: String = "Task<Void, Never>?"
    ) -> BiconditionalWitness {
        BiconditionalWitness(
            boolPropertyName: bool,
            boolTypeName: boolType,
            optionalPropertyName: optional,
            optionalTypeName: optionalType
        )
    }

    private let firstSeenAt = ISO8601DateFormatter().date(from: "2026-05-15T10:00:00Z")!

    // MARK: - analyze

    @Test("empty witnesses → empty suggestions")
    func emptyWitnesses() {
        let suggestions = BiconditionalInteractionTemplate.analyze(
            candidate: candidate(),
            witnesses: [],
            firstSeenAt: firstSeenAt
        )
        #expect(suggestions.isEmpty)
    }

    @Test("one witness → one suggestion with family:.biconditional")
    func oneWitness() {
        let suggestions = BiconditionalInteractionTemplate.analyze(
            candidate: candidate(),
            witnesses: [witness()],
            firstSeenAt: firstSeenAt
        )
        #expect(suggestions.count == 1)
        #expect(suggestions[0].family == .biconditional)
    }

    // MARK: - Predicate shape

    @Test("predicate is `state.<bool> == (state.<optional> != nil)`")
    func predicateShape() {
        let suggestion = BiconditionalInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        #expect(suggestion.predicate == "state.isLoading == (state.activeTask != nil)")
    }

    @Test("predicate substitutes the actual bool + optional names")
    func predicateSubstitutesNames() {
        let suggestion = BiconditionalInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(
                bool: "isShowingSheet",
                optional: "sheet",
                optionalType: "Sheet?"
            ),
            firstSeenAt: firstSeenAt
        )
        #expect(suggestion.predicate == "state.isShowingSheet == (state.sheet != nil)")
    }

    // MARK: - Score / tier

    @Test("score lands in .possible band (20-39)")
    func scoreInPossibleBand() {
        let suggestion = BiconditionalInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        #expect(suggestion.score >= 20)
        #expect(suggestion.score < 40)
        #expect(suggestion.tier == .possible)
    }

    // MARK: - Explainability

    @Test("whySuggested names the bool + optional field shapes")
    func whySuggestedExplains() {
        let suggestion = BiconditionalInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        let combined = suggestion.whySuggested.joined(separator: " | ")
        #expect(combined.contains("isLoading: Bool"))
        #expect(combined.contains("activeTask: Task<Void, Never>?"))
    }

    @Test("whyMightBeWrong calls out the calibration-difficulty + Cartesian + init() caveats")
    func whyMightBeWrongCaveats() {
        let suggestion = BiconditionalInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        let combined = suggestion.whyMightBeWrong.joined(separator: " | ")
        #expect(combined.contains("trickiest"))
        #expect(combined.contains("Cartesian-product"))
        #expect(combined.contains("init()"))
    }

    // MARK: - Identity

    @Test("identity stable for same (family, reducer, predicate)")
    func identityStability() {
        let first = BiconditionalInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        let second = BiconditionalInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        #expect(first.identity == second.identity)
    }

    @Test("identity varies by witness")
    func identityVariesByWitness() {
        let alpha = BiconditionalInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(bool: "isLoading", optional: "activeTask"),
            firstSeenAt: firstSeenAt
        )
        let beta = BiconditionalInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(bool: "isShowingSheet", optional: "sheet"),
            firstSeenAt: firstSeenAt
        )
        #expect(alpha.identity != beta.identity)
    }
}
