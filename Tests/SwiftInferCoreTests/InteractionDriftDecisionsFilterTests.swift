import Foundation
import Testing
@testable import SwiftInferCore

// V2.0 accept-check follow-up — wires the InteractionDriftDetector's
// new decisions filter (the M10 deferral). Suggestions with recorded
// decisions now skip drift warnings.

@Suite("InteractionDriftDetector — decisions filter")
struct InteractionDriftDecisionsFilterTests {

    private let now = ISO8601DateFormatter().date(from: "2026-05-15T12:00:00Z")!

    private func suggestion(
        predicate: String
    ) -> InteractionInvariantSuggestion {
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .cardinality,
            reducerQualifiedName: "Inbox.body",
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: .cardinality,
            reducerQualifiedName: "Inbox.body",
            reducerLocation: "F.swift:1",
            stateTypeName: "Inbox.State",
            actionTypeName: "Inbox.Action",
            predicate: predicate,
            score: 80,
            tier: .strong,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: now
        )
    }

    private func decision(
        for identity: String,
        decision: InteractionDecision = .accepted
    ) -> InteractionDecisionRecord {
        InteractionDecisionRecord(
            identityHash: identity,
            family: .cardinality,
            scoreAtDecision: 80,
            tier: .strong,
            reducerQualifiedName: "Inbox.body",
            decision: decision,
            timestamp: now
        )
    }

    @Test("nil decisions preserves the M10.0 no-filter behavior")
    func nilDecisionsBehavesLikeM10Zero() {
        let target = suggestion(predicate: "p1")
        let warnings = InteractionDriftDetector.warnings(
            currentSuggestions: [target],
            baseline: .empty,
            decisions: nil
        )
        #expect(warnings.count == 1)
    }

    @Test("supplied decisions filter out suggestions the user already accepted")
    func acceptedSuppressesWarning() {
        let target = suggestion(predicate: "p1")
        let decisions = InteractionDecisions(records: [
            decision(for: target.identity.normalized, decision: .accepted)
        ])
        let warnings = InteractionDriftDetector.warnings(
            currentSuggestions: [target],
            baseline: .empty,
            decisions: decisions
        )
        #expect(warnings.isEmpty)
    }

    @Test("every decision class suppresses the warning — accepted / rejected / skipped")
    func allDecisionClassesSuppress() {
        for kind in InteractionDecision.allCases {
            let target = suggestion(predicate: "p-\(kind.rawValue)")
            let decisions = InteractionDecisions(records: [
                decision(for: target.identity.normalized, decision: kind)
            ])
            let warnings = InteractionDriftDetector.warnings(
                currentSuggestions: [target],
                baseline: .empty,
                decisions: decisions
            )
            #expect(warnings.isEmpty, "expected \(kind.rawValue) to suppress drift")
        }
    }

    @Test("suggestions without recorded decisions still warn when Strong + not in baseline")
    func undecidedSuggestionsStillWarn() {
        let undecided = suggestion(predicate: "p-undecided")
        let knownAccepted = suggestion(predicate: "p-accepted")
        let decisions = InteractionDecisions(records: [
            decision(for: knownAccepted.identity.normalized)
        ])
        let warnings = InteractionDriftDetector.warnings(
            currentSuggestions: [undecided, knownAccepted],
            baseline: .empty,
            decisions: decisions
        )
        #expect(warnings.count == 1)
        #expect(warnings[0].predicate == "p-undecided")
    }
}
