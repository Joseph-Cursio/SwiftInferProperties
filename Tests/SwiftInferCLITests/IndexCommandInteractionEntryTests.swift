import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// V1.141 — `IndexCommand.buildInteractionEntry` projects an
/// `InteractionInvariantSuggestion` (plus its joined
/// `InteractionDecisionRecord`, if any) onto an `InteractionIndexEntry`.
/// The interaction analog of `IndexCommandBuildEntryTests`.
@Suite("IndexCommand — V1.141 interaction suggestion → InteractionIndexEntry projection")
struct IndexCommandInteractionEntryTests {

    // MARK: - Fixtures

    private static func makeSuggestion(
        family: InteractionInvariantFamily = .idempotence,
        reducer: String = "NavFeature.reduce",
        predicate: String = "reduce(reduce(s, .dismiss), .dismiss) == reduce(s, .dismiss)",
        score: Int = 40,
        tier: Tier = .likely,
        moduleName: String? = nil
    ) -> InteractionInvariantSuggestion {
        InteractionInvariantSuggestion(
            identity: SuggestionIdentity(
                canonicalInput: "\(family.rawValue)::\(reducer)::\(predicate)"
            ),
            family: family,
            reducerQualifiedName: reducer,
            reducerLocation: "/foo/NavFeature.swift:12",
            stateTypeName: "State",
            actionTypeName: "Action",
            predicate: predicate,
            score: score,
            tier: tier,
            whySuggested: ["why"],
            whyMightBeWrong: ["caveat"],
            firstSeenAt: Date(timeIntervalSince1970: 1_770_000_000),
            moduleName: moduleName
        )
    }

    private static func makeRecord(
        for suggestion: InteractionInvariantSuggestion,
        decision: InteractionDecision,
        timestamp: Date = Date(timeIntervalSince1970: 1_780_000_000)
    ) -> InteractionDecisionRecord {
        InteractionDecisionRecord(
            identityHash: suggestion.identity.normalized,
            family: suggestion.family,
            scoreAtDecision: suggestion.score,
            tier: suggestion.tier,
            reducerQualifiedName: suggestion.reducerQualifiedName,
            decision: decision,
            timestamp: timestamp
        )
    }

    // MARK: - Projection without decision

    @Test("V1.141 — buildInteractionEntry without decision: decision/decisionAt nil, columns mapped")
    func withoutDecision() {
        let suggestion = Self.makeSuggestion(moduleName: "Nav")
        let now = "2026-06-14T12:00:00Z"
        let entry = SwiftInferCommand.Index.buildInteractionEntry(
            from: suggestion,
            decisionsByHash: [:],
            now: now
        )
        #expect(entry.identityHash == suggestion.identity.display)
        #expect(entry.family == "idempotence")
        #expect(entry.reducerQualifiedName == "NavFeature.reduce")
        #expect(entry.stateTypeName == "State")
        #expect(entry.actionTypeName == "Action")
        #expect(entry.predicate == suggestion.predicate)
        #expect(entry.location == "/foo/NavFeature.swift:12")
        #expect(entry.moduleName == "Nav")
        #expect(entry.score == 40)
        #expect(entry.tier == "Likely")   // 40 → Likely
        #expect(entry.decision == nil)
        #expect(entry.decisionAt == nil)
        #expect(entry.firstSeenAt == now)
        #expect(entry.lastSeenAt == now)
    }

    // MARK: - Projection with decision

    @Test("V1.141 — buildInteractionEntry with accept decision: copies decision + timestamp")
    func withAcceptDecision() {
        let suggestion = Self.makeSuggestion()
        let decisionDate = Date(timeIntervalSince1970: 1_780_000_000)
        let record = Self.makeRecord(for: suggestion, decision: .accepted, timestamp: decisionDate)
        let entry = SwiftInferCommand.Index.buildInteractionEntry(
            from: suggestion,
            decisionsByHash: [suggestion.identity.normalized: record],
            now: "2026-06-14T12:00:00Z"
        )
        #expect(entry.decision == "accepted")
        #expect(entry.decisionAt == SwiftInferCommand.Index.isoTimestamp(from: decisionDate))
    }

    @Test("V1.141 — acceptedAsConformance decision maps to its rawValue")
    func withAcceptAsConformanceDecision() {
        let suggestion = Self.makeSuggestion()
        let record = Self.makeRecord(for: suggestion, decision: .acceptedAsConformance)
        let entry = SwiftInferCommand.Index.buildInteractionEntry(
            from: suggestion,
            decisionsByHash: [suggestion.identity.normalized: record],
            now: "2026-06-14T12:00:00Z"
        )
        #expect(entry.decision == "accepted-as-conformance")
    }

    @Test("V1.141 — buildInteractionEntry joins on normalized (no 0x prefix) form")
    func joinsOnNormalized() {
        let suggestion = Self.makeSuggestion()
        let record = Self.makeRecord(for: suggestion, decision: .rejected)
        let entry = SwiftInferCommand.Index.buildInteractionEntry(
            from: suggestion,
            decisionsByHash: [suggestion.identity.normalized: record],
            now: "2026-06-14T12:00:00Z"
        )
        #expect(entry.decision == "rejected")
        // The entry stores the display hash (0x-prefixed); the join key is the
        // normalized (no-0x) form.
        #expect(entry.identityHash.hasPrefix("0x"))
        #expect(!suggestion.identity.normalized.hasPrefix("0x"))
    }

    // MARK: - Family + tier mapping

    @Test("V1.141 — family rawValue + verified tier map through")
    func familyAndTierMapping() {
        let suggestion = Self.makeSuggestion(
            family: .referentialIntegrity,
            score: 80,
            tier: .verified
        )
        let entry = SwiftInferCommand.Index.buildInteractionEntry(
            from: suggestion,
            decisionsByHash: [:],
            now: "2026-06-14T12:00:00Z"
        )
        #expect(entry.family == "referential-integrity")
        #expect(entry.tier == "Verified")
    }
}
