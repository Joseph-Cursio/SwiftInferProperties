import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

@Suite("MetricsRenderer — V1.4.1 §17.2 aggregation")
struct MetricsRendererTests {

    // MARK: - Fixtures

    private static func record(
        identityHash: String,
        template: String,
        decision: Decision,
        tier: Tier = .strong,
        score: Int = 80,
        timestampOffset: TimeInterval = 0
    ) -> DecisionRecord {
        DecisionRecord(
            identityHash: identityHash,
            template: template,
            scoreAtDecision: score,
            tier: tier,
            decision: decision,
            timestamp: Date(timeIntervalSince1970: timestampOffset)
        )
    }

    // MARK: - Per-template aggregation

    @Test("Three decisions on same template aggregate to one row with correct totals")
    func threeDecisionsOneTemplate() {
        let decisions = Decisions(records: [
            Self.record(identityHash: "AA", template: "round-trip", decision: .accepted),
            Self.record(identityHash: "BB", template: "round-trip", decision: .rejected),
            Self.record(identityHash: "CC", template: "round-trip", decision: .skipped),
        ])
        let rows = MetricsRenderer.templateRows(from: decisions)
        #expect(rows.count == 1)
        #expect(rows[0].template == "round-trip")
        #expect(rows[0].total == 3)
        #expect(rows[0].accepted == 1)
        #expect(rows[0].rejected == 1)
        #expect(rows[0].skipped == 1)
    }

    @Test("`acceptedAsConformance` counts toward the accepted bucket (not its own)")
    func acceptedAsConformanceCountsAsAccepted() {
        let decisions = Decisions(records: [
            Self.record(identityHash: "AA", template: "round-trip", decision: .accepted),
            Self.record(identityHash: "BB", template: "round-trip", decision: .acceptedAsConformance),
        ])
        let rows = MetricsRenderer.templateRows(from: decisions)
        #expect(rows.count == 1)
        #expect(rows[0].accepted == 2)
        #expect(rows[0].rejected == 0)
        #expect(rows[0].acceptanceRate == 1.0)
    }

    @Test("Multiple templates produce one row each; sorted by total desc, name asc")
    func multipleTemplatesSortedDeterministically() {
        var records: [DecisionRecord] = []
        for index in 0..<5 {
            records.append(Self.record(
                identityHash: "RT\(index)",
                template: "round-trip",
                decision: .accepted
            ))
        }
        for index in 0..<3 {
            records.append(Self.record(
                identityHash: "ID\(index)",
                template: "idempotence",
                decision: .accepted
            ))
        }
        for index in 0..<3 {
            records.append(Self.record(
                identityHash: "CM\(index)",
                template: "commutativity",
                decision: .rejected
            ))
        }
        let rows = MetricsRenderer.templateRows(from: Decisions(records: records))
        #expect(rows.count == 3)
        // Highest total first, then ties alphabetically.
        #expect(rows[0].template == "round-trip")
        #expect(rows[1].template == "commutativity")
        #expect(rows[2].template == "idempotence")
    }

    // MARK: - <20 decisions advisory

    @Test("Template with fewer than 20 decisions surfaces low-count flag")
    func lowCountFlagForUnder20() {
        let row = MetricsRenderer.TemplateRow(
            template: "round-trip", total: 19, accepted: 5, rejected: 10, skipped: 4
        )
        #expect(row.isLowCount == true)
        #expect(row.isRetirementCandidate == false)
    }

    @Test("Template at 20 decisions is no longer low-count")
    func atThresholdNotLowCount() {
        let row = MetricsRenderer.TemplateRow(
            template: "round-trip", total: 20, accepted: 5, rejected: 10, skipped: 5
        )
        #expect(row.isLowCount == false)
    }

    @Test("Retirement candidate: ≥20 decisions and acceptance < 50%")
    func retirementCandidateBelowFiftyPercent() {
        let row = MetricsRenderer.TemplateRow(
            template: "round-trip", total: 20, accepted: 9, rejected: 11, skipped: 0
        )
        #expect(row.acceptanceRate == 0.45)
        #expect(row.isRetirementCandidate == true)
    }

    @Test("Above 50% acceptance with ≥20 decisions is not a retirement candidate")
    func aboveFiftyNotRetirement() {
        let row = MetricsRenderer.TemplateRow(
            template: "round-trip", total: 20, accepted: 11, rejected: 9, skipped: 0
        )
        #expect(row.isRetirementCandidate == false)
    }

    // MARK: - Tier rows

    @Test("Tier rows emit one entry per tier with at least one decision, in canonical order")
    func tierRowsCanonicalOrder() {
        let decisions = Decisions(records: [
            Self.record(identityHash: "AA", template: "round-trip", decision: .accepted, tier: .strong),
            Self.record(identityHash: "BB", template: "round-trip", decision: .rejected, tier: .strong),
            Self.record(identityHash: "CC", template: "idempotence", decision: .accepted, tier: .likely),
            Self.record(identityHash: "DD", template: "equivalence-class", decision: .skipped, tier: .advisory),
        ])
        let rows = MetricsRenderer.tierRows(from: decisions)
        #expect(rows.count == 3)
        // Tier.allCases is strong → likely → possible → suppressed → advisory.
        #expect(rows[0].tier == .strong)
        #expect(rows[1].tier == .likely)
        #expect(rows[2].tier == .advisory)
        #expect(rows[0].total == 2)
        #expect(rows[0].accepted == 1)
        #expect(rows[1].acceptanceRate == 1.0)
        #expect(rows[2].acceptanceRate == 0.0)
    }

    // MARK: - Render — end-to-end

    @Test("Render emits decision count + per-template + per-tier sections")
    func renderEndToEnd() {
        let decisions = Decisions(records: [
            Self.record(identityHash: "AA", template: "round-trip", decision: .accepted, tier: .strong),
            Self.record(identityHash: "BB", template: "idempotence", decision: .rejected, tier: .likely),
        ])
        let output = MetricsRenderer.render(
            decisions: decisions,
            sources: ["~/calibration/swift-collections/.swiftinfer/decisions.json"]
        )
        #expect(output.contains("swift-infer metrics — calibration aggregate (PRD §17.2)"))
        #expect(output.contains("Decisions: 2 across 1 source"))
        #expect(output.contains("Per-template adoption:"))
        #expect(output.contains("round-trip"))
        #expect(output.contains("idempotence"))
        #expect(output.contains("Tier-mix at decision time:"))
        #expect(output.contains("Strong"))
        #expect(output.contains("Likely"))
        // Low-count advisory should fire for both templates.
        #expect(output.contains("fewer than 20 decisions"))
    }

    @Test("Render with no decisions emits 'no decisions yet' lines")
    func renderEmpty() {
        let output = MetricsRenderer.render(decisions: .empty, sources: [])
        #expect(output.contains("Decisions: 0 across 0 sources"))
        #expect(output.contains("(no decisions yet)"))
    }

    @Test("Multi-source header pluralizes correctly")
    func multiSourceHeader() {
        let output = MetricsRenderer.render(
            decisions: .empty,
            sources: ["a.json", "b.json", "c.json"]
        )
        #expect(output.contains("Decisions: 0 across 3 sources"))
        #expect(output.contains("1. a.json"))
        #expect(output.contains("2. b.json"))
        #expect(output.contains("3. c.json"))
    }
}
