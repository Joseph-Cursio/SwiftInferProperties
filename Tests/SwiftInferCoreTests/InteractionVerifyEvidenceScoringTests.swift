import Foundation
@testable import SwiftInferCore
import Testing

/// Cycle 112 — unit tests for the verify-evidence consumer fold (the
/// `InteractionInvariantSuggestion` analogue of `VerifyEvidenceScoringTests`).
/// Exhaustive over the five outcomes × the Finding-G gate; pure, no disk.
@Suite("InteractionVerifyEvidenceScoring — verify-as-signal fold (cycle 112)")
struct InteractionVerifyEvidenceScoringTests {

    // MARK: - Fixtures

    private func suggestion(
        family: InteractionInvariantFamily,
        predicate: String,
        score: Int,
        tier: Tier
    ) -> InteractionInvariantSuggestion {
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: family,
            reducerQualifiedName: "Inbox.body",
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: family,
            reducerQualifiedName: "Inbox.body",
            reducerLocation: "Sources/MyApp/Inbox.swift:42",
            stateTypeName: "Inbox.State",
            actionTypeName: "Inbox.Action",
            predicate: predicate,
            score: score,
            tier: tier,
            whySuggested: ["base signal"],
            whyMightBeWrong: ["base caveat"],
            firstSeenAt: ISO8601DateFormatter().date(from: "2026-05-15T10:00:00Z")!
        )
    }

    /// A `.likely` idempotence pick at the cycle-107 promotion score (40).
    private func idempotenceLikely() -> InteractionInvariantSuggestion {
        suggestion(family: .idempotence, predicate: ".refresh", score: 40, tier: .likely)
    }

    private func evidence(
        for suggestion: InteractionInvariantSuggestion,
        outcome: VerifyEvidenceOutcome,
        detail: String? = nil
    ) -> [String: VerifyEvidence] {
        [
            suggestion.identity.normalized: VerifyEvidence(
                identityHash: suggestion.identity.normalized,
                template: suggestion.family.rawValue,
                outcome: outcome,
                detail: detail,
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                swiftInferVersion: "1.118.0"
            )
        ]
    }

    // MARK: - measuredBothPass

    @Test("bothPass lifts a .likely idempotence pick to .verified (40 + 50 = 90 → strong → verified)")
    func bothPassPromotesIdempotenceToVerified() {
        let pick = idempotenceLikely()
        let graded = InteractionVerifyEvidenceScoring.applied(
            to: [pick],
            evidenceByIdentity: evidence(for: pick, outcome: .measuredBothPass, detail: "totalRuns=1024 clean=1024")
        )
        #expect(graded.count == 1)
        #expect(graded[0].score == 90)
        #expect(graded[0].tier == .verified)
        // The bothPass detail joins the "why suggested" arm.
        #expect(graded[0].whySuggested.contains { $0.contains("bothPass") && $0.contains("totalRuns=1024") })
    }

    @Test("bothPass with nil detail still records a why-suggested line")
    func bothPassNilDetailFallsBackToDefaultProse() {
        let pick = idempotenceLikely()
        let graded = InteractionVerifyEvidenceScoring.applied(
            to: [pick],
            evidenceByIdentity: evidence(for: pick, outcome: .measuredBothPass, detail: nil)
        )
        #expect(graded[0].whySuggested.contains { $0.contains("property held at execution") })
    }

    // MARK: - Finding-G gate (the load-bearing case)

    @Test("bothPass does NOT promote a cardinality pick — Finding-G gate pins .possible even when measured")
    func bothPassRespectsFindingGGateForCardinality() {
        // Cardinality carries a swiftProjectLintDeferral, so the gate must
        // clamp it to .possible regardless of the +50 evidence weight.
        let pick = suggestion(family: .cardinality, predicate: "atMostOne(...)", score: 30, tier: .possible)
        let graded = InteractionVerifyEvidenceScoring.applied(
            to: [pick],
            evidenceByIdentity: evidence(for: pick, outcome: .measuredBothPass)
        )
        #expect(graded[0].score == 80)          // score still rises…
        #expect(graded[0].tier == .possible)    // …but the tier is gated.
    }

    @Test("bothPass does NOT promote a biconditional pick — gate pins .possible")
    func bothPassRespectsFindingGGateForBiconditional() {
        let pick = suggestion(family: .biconditional, predicate: "bothOrNeither(...)", score: 30, tier: .possible)
        let graded = InteractionVerifyEvidenceScoring.applied(
            to: [pick],
            evidenceByIdentity: evidence(for: pick, outcome: .measuredBothPass)
        )
        #expect(graded[0].tier == .possible)
    }

    // MARK: - measuredDefaultFails (veto)

    @Test("defaultFails collapses any pick to .suppressed and records a caveat")
    func defaultFailsSuppresses() {
        let pick = idempotenceLikely()
        let graded = InteractionVerifyEvidenceScoring.applied(
            to: [pick],
            evidenceByIdentity: evidence(for: pick, outcome: .measuredDefaultFails, detail: "at sequence index 3")
        )
        #expect(graded[0].tier == .suppressed)
        #expect(graded[0].whyMightBeWrong.contains { $0.contains("defaultFails") && $0.contains("index 3") })
    }

    // MARK: - Score-neutral outcomes + no evidence

    @Test("edgeCaseAdvisory / error / architecturalCoveragePending pass through unchanged")
    func neutralOutcomesPassThrough() {
        let pick = idempotenceLikely()
        let neutral: [VerifyEvidenceOutcome] = [
            .measuredEdgeCaseAdvisory, .measuredError, .architecturalCoveragePending
        ]
        for outcome in neutral {
            let graded = InteractionVerifyEvidenceScoring.applied(
                to: [pick],
                evidenceByIdentity: evidence(for: pick, outcome: outcome)
            )
            #expect(graded[0] == pick, "outcome \(outcome) should be score-neutral")
        }
    }

    @Test("a pick with no matching evidence is returned identically (== holds)")
    func noEvidencePassesThroughUnchanged() {
        let pick = idempotenceLikely()
        let graded = InteractionVerifyEvidenceScoring.applied(to: [pick], evidenceByIdentity: [:])
        #expect(graded == [pick])
    }

    @Test("order is preserved and only matching picks are re-graded")
    func orderPreservedAndSelective() {
        let idem = idempotenceLikely()
        let other = suggestion(family: .conservation, predicate: "state.a == state.b.count", score: 30, tier: .possible)
        // Evidence only for the idempotence pick.
        let graded = InteractionVerifyEvidenceScoring.applied(
            to: [other, idem],
            evidenceByIdentity: evidence(for: idem, outcome: .measuredBothPass)
        )
        #expect(graded[0] == other)             // untouched, same position
        #expect(graded[1].tier == .verified)    // re-graded
    }
}
