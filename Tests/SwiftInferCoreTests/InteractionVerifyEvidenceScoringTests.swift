import Foundation
@testable import SwiftInferCore
import Testing

/// Cycle 112 (+ 135/136) — unit tests for the verify-evidence consumer fold
/// (the `InteractionInvariantSuggestion` analogue of
/// `VerifyEvidenceScoringTests`). Exhaustive over the five outcomes × the
/// Finding-G gate × the cycle-135 full-coverage pin-overrule; pure, no disk.
@Suite("InteractionVerifyEvidenceScoring — verify-as-signal fold (cycle 112 + 135/136)")
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
        detail: String? = nil,
        excludedActionCount: Int? = nil
    ) -> [String: VerifyEvidence] {
        [
            suggestion.identity.normalized: VerifyEvidence(
                identityHash: suggestion.identity.normalized,
                template: suggestion.family.rawValue,
                outcome: outcome,
                detail: detail,
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                swiftInferVersion: "1.118.0",
                excludedActionCount: excludedActionCount
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

    // MARK: - Finding-G gate + cycle-135/136 pin-overrule (load-bearing)

    @Test("bothPass with UNRECORDED coverage (legacy nil) keeps the cardinality pin at .possible")
    func bothPassLegacyCoverageRespectsCardinalityPin() {
        // Cardinality carries a swiftProjectLintDeferral. With coverage
        // unrecorded (nil — evidence written before cycle 136), the overrule
        // does not fire: the gate clamps to .possible despite the +50 weight.
        let pick = suggestion(family: .cardinality, predicate: "atMostOne(...)", score: 30, tier: .possible)
        let graded = InteractionVerifyEvidenceScoring.applied(
            to: [pick],
            evidenceByIdentity: evidence(for: pick, outcome: .measuredBothPass)
        )
        #expect(graded[0].score == 80)          // score still rises…
        #expect(graded[0].tier == .possible)    // …but the tier is gated.
    }

    @Test("bothPass at PARTIAL coverage (excludedActionCount > 0) keeps the cardinality pin at .possible")
    func bothPassPartialCoverageRespectsCardinalityPin() {
        // The failure mode lives in the excluded composition actions, so a
        // partial bothPass is biased toward false-pass — no overrule.
        let pick = suggestion(family: .cardinality, predicate: "atMostOne(...)", score: 30, tier: .possible)
        let graded = InteractionVerifyEvidenceScoring.applied(
            to: [pick],
            evidenceByIdentity: evidence(
                for: pick, outcome: .measuredBothPass, excludedActionCount: 2
            )
        )
        #expect(graded[0].tier == .possible)
        #expect(!graded[0].whySuggested.contains { $0.contains("overruled") })
    }

    @Test("bothPass at FULL coverage (excludedActionCount == 0) OVERRULES the cardinality pin → .verified")
    func bothPassFullCoverageOverrulesCardinalityPin() {
        // Cycle 135/136: a full-coverage measured bothPass is sound
        // per-candidate proof the reducer enforces the mutex itself, so it
        // overrules the Finding-G pin and promotes via the ungated tier
        // (30 + 50 = 80 → .strong → .verified) with a disclosure.
        let pick = suggestion(family: .cardinality, predicate: "atMostOne(...)", score: 30, tier: .possible)
        let graded = InteractionVerifyEvidenceScoring.applied(
            to: [pick],
            evidenceByIdentity: evidence(
                for: pick, outcome: .measuredBothPass, excludedActionCount: 0
            )
        )
        #expect(graded[0].score == 80)
        #expect(graded[0].tier == .verified)
        #expect(graded[0].whySuggested.contains {
            $0.contains("overruled") && $0.contains("0 excluded actions")
        })
    }

    @Test("bothPass at FULL coverage overrules the biconditional pin → .verified")
    func bothPassFullCoverageOverrulesBiconditionalPin() {
        let pick = suggestion(family: .biconditional, predicate: "bothOrNeither(...)", score: 30, tier: .possible)
        let graded = InteractionVerifyEvidenceScoring.applied(
            to: [pick],
            evidenceByIdentity: evidence(
                for: pick, outcome: .measuredBothPass, excludedActionCount: 0
            )
        )
        #expect(graded[0].tier == .verified)
    }

    @Test("an UNGATED family (conservation) is unaffected by coverage — full-coverage bothPass still .verified")
    func bothPassUngatedFamilyIgnoresCoverage() {
        // Conservation carries no deferral, so the overrule branch is moot:
        // promotion happens through the ungated tier regardless of coverage,
        // and no overrule disclosure is appended.
        let pick = suggestion(family: .conservation, predicate: "state.a == state.b.count", score: 30, tier: .possible)
        let graded = InteractionVerifyEvidenceScoring.applied(
            to: [pick],
            evidenceByIdentity: evidence(
                for: pick, outcome: .measuredBothPass, excludedActionCount: 0
            )
        )
        #expect(graded[0].tier == .verified)
        #expect(!graded[0].whySuggested.contains { $0.contains("overruled") })
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
