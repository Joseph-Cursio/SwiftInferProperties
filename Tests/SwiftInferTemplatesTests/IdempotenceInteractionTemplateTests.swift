import Foundation
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// V2.0 M4.C — IdempotenceInteractionTemplate tests. Pure: given
// a candidate + witness, assert on the emitted suggestion's
// structure.

@Suite("IdempotenceInteractionTemplate — V2.0 M4.C suggestion emission")
struct IdempotenceInteractionTemplateTests {

    private func candidate(
        functionName: String = "reduce",
        stateTypeName: String = "AppState",
        actionTypeName: String = "AppAction"
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/MyApp/F.swift:1",
            enclosingTypeName: nil,
            functionName: functionName,
            signatureShape: .stateActionReturnsState,
            stateTypeName: stateTypeName,
            actionTypeName: actionTypeName,
            carrierKind: .elmStyle
        )
    }

    private func witness(
        name: String = "refresh",
        kind: IdempotenceWitness.MatchKind = .exactName
    ) -> IdempotenceWitness {
        IdempotenceWitness(actionCaseName: name, matchKind: kind)
    }

    private let firstSeenAt = ISO8601DateFormatter().date(from: "2026-05-15T10:00:00Z")!

    // MARK: - analyze

    @Test("empty witnesses → empty suggestions")
    func emptyWitnesses() {
        let suggestions = IdempotenceInteractionTemplate.analyze(
            candidate: candidate(),
            witnesses: [],
            firstSeenAt: firstSeenAt
        )
        #expect(suggestions.isEmpty)
    }

    @Test("one witness → one suggestion with family:.idempotence + dot-shorthand predicate")
    func oneWitnessOneSuggestion() {
        let suggestions = IdempotenceInteractionTemplate.analyze(
            candidate: candidate(),
            witnesses: [witness(name: "refresh")],
            firstSeenAt: firstSeenAt
        )
        #expect(suggestions.count == 1)
        let suggestion = suggestions[0]
        #expect(suggestion.family == .idempotence)
        #expect(suggestion.predicate == ".refresh")
    }

    @Test("multiple witnesses → multiple suggestions, one per witness")
    func multipleWitnesses() {
        let suggestions = IdempotenceInteractionTemplate.analyze(
            candidate: candidate(),
            witnesses: [
                witness(name: "refresh"),
                witness(name: "dismiss"),
                witness(name: "setColor", kind: .namePrefix)
            ],
            firstSeenAt: firstSeenAt
        )
        #expect(suggestions.count == 3)
        #expect(suggestions.map(\.predicate) == [".refresh", ".dismiss", ".setColor"])
    }

    // MARK: - Suggestion shape

    @Test("score lands in the .possible band (20-39)")
    func scoreInPossibleBand() {
        let suggestion = IdempotenceInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        #expect(suggestion.score >= 20)
        #expect(suggestion.score < 40)
        #expect(suggestion.tier == .possible)
    }

    @Test("exact-name witness — whySuggested mentions the curated list")
    func whySuggestedExactName() {
        let suggestion = IdempotenceInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(name: "refresh", kind: .exactName),
            firstSeenAt: firstSeenAt
        )
        let combined = suggestion.whySuggested.joined(separator: " | ")
        #expect(combined.contains(".refresh"))
        #expect(combined.contains("exact-match"))
    }

    @Test("prefix-name witness — whySuggested mentions the payload-aware framing")
    func whySuggestedPrefix() {
        let suggestion = IdempotenceInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(name: "setColor", kind: .namePrefix),
            firstSeenAt: firstSeenAt
        )
        let combined = suggestion.whySuggested.joined(separator: " | ")
        #expect(combined.contains(".setColor"))
        #expect(combined.contains("name-prefix"))
        #expect(combined.contains("payload"))
    }

    @Test("whyMightBeWrong always calls out the name-based detection limitation")
    func whyMightBeWrongNameBased() {
        let suggestion = IdempotenceInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        let combined = suggestion.whyMightBeWrong.joined(separator: " | ")
        #expect(combined.contains("name-based"))
    }

    @Test("prefix-match witness adds an extra caveat about payload variance")
    func whyMightBeWrongPrefixCaveat() {
        let exactSuggestion = IdempotenceInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(name: "refresh", kind: .exactName),
            firstSeenAt: firstSeenAt
        )
        let prefixSuggestion = IdempotenceInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(name: "setColor", kind: .namePrefix),
            firstSeenAt: firstSeenAt
        )
        // Prefix has more caveats than exact-name.
        #expect(prefixSuggestion.whyMightBeWrong.count > exactSuggestion.whyMightBeWrong.count)
    }

    @Test("identity hash is stable for the same (family, reducer, predicate)")
    func identityStability() {
        let first = IdempotenceInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        let second = IdempotenceInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(),
            firstSeenAt: firstSeenAt
        )
        #expect(first.identity == second.identity)
    }

    @Test("identity hash varies by action case")
    func identityVariesByCase() {
        let alpha = IdempotenceInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(name: "refresh"),
            firstSeenAt: firstSeenAt
        )
        let beta = IdempotenceInteractionTemplate.makeSuggestion(
            candidate: candidate(),
            witness: witness(name: "reset"),
            firstSeenAt: firstSeenAt
        )
        #expect(alpha.identity != beta.identity)
    }
}
