import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

@Suite("MetricsRenderer — V1.64.D verify-evidence cross-reference")
struct MetricsRendererVerifyEvidenceTests {

    // MARK: - Fixtures

    private static func decision(
        _ identityHash: String,
        _ decision: Decision,
        template: String = "round-trip"
    ) -> DecisionRecord {
        DecisionRecord(
            identityHash: identityHash,
            template: template,
            scoreAtDecision: 80,
            tier: .strong,
            decision: decision,
            timestamp: Date(timeIntervalSince1970: 0)
        )
    }

    private static func evidence(
        _ identityHash: String,
        _ outcome: VerifyEvidenceOutcome
    ) -> VerifyEvidence {
        VerifyEvidence(
            identityHash: identityHash,
            template: "round-trip",
            outcome: outcome,
            detail: nil,
            capturedAt: Date(timeIntervalSince1970: 0),
            swiftInferVersion: "1.64.0"
        )
    }

    // MARK: - evidenceRows join

    @Test("evidenceRows joins by identityHash and buckets per Decision")
    func evidenceRowsJoinsAndBuckets() {
        let decisions = Decisions(records: [
            Self.decision("AAA1111111111111", .accepted),
            Self.decision("BBB2222222222222", .accepted),
            Self.decision("CCC3333333333333", .rejected)
        ])
        let evidence = VerifyEvidenceLog(records: [
            Self.evidence("AAA1111111111111", .measuredBothPass),
            Self.evidence("BBB2222222222222", .measuredEdgeCaseAdvisory),
            Self.evidence("CCC3333333333333", .measuredDefaultFails)
        ])
        let rows = MetricsRenderer.evidenceRows(decisions: decisions, evidence: evidence)
        #expect(rows.count == 2)
        let accepted = rows.first { $0.decision == .accepted }
        #expect(accepted?.total == 2)
        #expect(accepted?.bothPass == 1)
        #expect(accepted?.edgeCaseAdvisory == 1)
        let rejected = rows.first { $0.decision == .rejected }
        #expect(rejected?.total == 1)
        #expect(rejected?.defaultFails == 1)
    }

    @Test("decisions with no matching evidence are excluded from the rows")
    func decisionsWithoutEvidenceExcluded() {
        let decisions = Decisions(records: [
            Self.decision("AAA1111111111111", .accepted),
            Self.decision("NOEVIDENCE000000", .accepted)
        ])
        let evidence = VerifyEvidenceLog(records: [
            Self.evidence("AAA1111111111111", .measuredBothPass)
        ])
        let rows = MetricsRenderer.evidenceRows(decisions: decisions, evidence: evidence)
        #expect(rows.count == 1)
        #expect(rows[0].decision == .accepted)
        #expect(rows[0].total == 1)
    }

    @Test("rows follow Decision.allCases order")
    func rowsFollowDecisionAllCasesOrder() {
        let decisions = Decisions(records: [
            Self.decision("DDD4444444444444", .skipped),
            Self.decision("AAA1111111111111", .accepted),
            Self.decision("CCC3333333333333", .rejected)
        ])
        let evidence = VerifyEvidenceLog(records: [
            Self.evidence("AAA1111111111111", .measuredBothPass),
            Self.evidence("CCC3333333333333", .measuredDefaultFails),
            Self.evidence("DDD4444444444444", .architecturalCoveragePending)
        ])
        let rows = MetricsRenderer.evidenceRows(decisions: decisions, evidence: evidence)
        #expect(rows.map(\.decision) == [.accepted, .rejected, .skipped])
    }

    // MARK: - render section

    @Test("render with empty evidence emits the no-evidence sentinel")
    func renderEmptyEvidenceSentinel() {
        let output = MetricsRenderer.render(
            decisions: Decisions(records: [Self.decision("AAA1111111111111", .accepted)]),
            sources: ["x"],
            evidence: .empty
        )
        #expect(output.contains("Verify-evidence cross-reference (PRD §17.2):"))
        #expect(output.contains("(no verify evidence — run `swift-infer verify` to populate)"))
    }

    @Test("render with evidence emits the cross-reference table and matched count")
    func renderWithEvidenceEmitsTable() {
        let decisions = Decisions(records: [
            Self.decision("AAA1111111111111", .accepted),
            Self.decision("BBB2222222222222", .rejected),
            Self.decision("NOEVIDENCE000000", .skipped)
        ])
        let evidence = VerifyEvidenceLog(records: [
            Self.evidence("AAA1111111111111", .measuredBothPass),
            Self.evidence("BBB2222222222222", .measuredDefaultFails)
        ])
        let output = MetricsRenderer.render(
            decisions: decisions,
            sources: ["x"],
            evidence: evidence
        )
        #expect(output.contains("2 of 3 decisions have verify evidence."))
        #expect(output.contains("| Decision              | Total | bothPass |"))
        #expect(output.contains("| accepted "))
        #expect(output.contains("| rejected "))
        // The skipped decision has no evidence — no row for it.
        #expect(!output.contains("| skipped "))
    }

    @Test("render evidence section defaults to the sentinel when omitted")
    func renderDefaultsToSentinelWhenEvidenceOmitted() {
        let output = MetricsRenderer.render(
            decisions: Decisions(records: [Self.decision("AAA1111111111111", .accepted)]),
            sources: ["x"]
        )
        #expect(output.contains("(no verify evidence — run `swift-infer verify` to populate)"))
    }
}
