import Foundation
import Testing
@testable import SwiftInferCore

// V1.102 (cycle-99 calibration helper) — InteractionMetricsRenderer.
// Pure rendering: no I/O.

@Suite("InteractionMetricsRenderer — V1.102 markdown + plain rendering")
struct InteractionMetricsRendererTests {

    private let now = ISO8601DateFormatter().date(from: "2026-05-17T12:00:00Z")!

    private func record(
        identity: String,
        family: InteractionInvariantFamily,
        decision: InteractionDecision
    ) -> InteractionDecisionRecord {
        InteractionDecisionRecord(
            identityHash: identity,
            family: family,
            scoreAtDecision: 30,
            tier: .possible,
            reducerQualifiedName: "Test.body",
            decision: decision,
            timestamp: now
        )
    }

    @Test func markdownIncludesSourceListAndAllFamilyRows() {
        let report = InteractionDecisionsAggregator.aggregate(InteractionDecisions(records: [
            record(identity: "A", family: .cardinality, decision: .accepted)
        ]))
        let rendered = InteractionMetricsRenderer.render(
            report,
            sources: ["/tmp/foo.json", "/tmp/bar.json"],
            format: .markdown
        )
        #expect(rendered.contains("Sources: /tmp/foo.json, /tmp/bar.json"))
        #expect(rendered.contains("| Idempotence |"))
        #expect(rendered.contains("| Biconditional |"))
        #expect(rendered.contains("| Cardinality |"))
        #expect(rendered.contains("| Referential Integrity |"))
        #expect(rendered.contains("| Conservation |"))
        #expect(rendered.contains("| **Overall** |"))
    }

    @Test func markdownRendersAcceptanceRatePercent() {
        // 2 accepted / 3 decided = 67%
        let report = InteractionDecisionsAggregator.aggregate(InteractionDecisions(records: [
            record(identity: "A", family: .cardinality, decision: .accepted),
            record(identity: "B", family: .cardinality, decision: .accepted),
            record(identity: "C", family: .cardinality, decision: .rejected)
        ]))
        let rendered = InteractionMetricsRenderer.render(
            report,
            sources: ["test"],
            format: .markdown
        )
        // The row order is fixed; cardinality is 3rd family in display order
        let cardinalityLine = rendered.split(separator: "\n").first { $0.contains("| Cardinality |") }
        #expect(cardinalityLine?.contains("67%") == true)
    }

    @Test func emptyReportRendersDashesNotZeroPercent() {
        let report = InteractionDecisionsAggregator.aggregate(.empty)
        let rendered = InteractionMetricsRenderer.render(
            report,
            sources: ["empty"],
            format: .markdown
        )
        // Empty acceptance rate should render as "—" not "0%"
        #expect(rendered.contains("| — |"))
        #expect(!rendered.contains("| 0% |"))
    }

    @Test func skipRateBeyondThresholdGetsAsteriskAndFootnote() {
        // 4 skipped / 5 total = 80% skip rate — well above 30% threshold
        let report = InteractionDecisionsAggregator.aggregate(InteractionDecisions(records: [
            record(identity: "A", family: .biconditional, decision: .accepted),
            record(identity: "B", family: .biconditional, decision: .skipped),
            record(identity: "C", family: .biconditional, decision: .skipped),
            record(identity: "D", family: .biconditional, decision: .skipped),
            record(identity: "E", family: .biconditional, decision: .skipped)
        ]))
        let rendered = InteractionMetricsRenderer.render(
            report,
            sources: ["test"],
            format: .markdown
        )
        #expect(rendered.contains("80%*"))
        #expect(rendered.contains("refinement threshold"))
    }

    @Test func plainFormatRendersFixedWidthColumns() {
        let report = InteractionDecisionsAggregator.aggregate(InteractionDecisions(records: [
            record(identity: "A", family: .cardinality, decision: .accepted)
        ]))
        let rendered = InteractionMetricsRenderer.render(
            report,
            sources: ["test"],
            format: .plain
        )
        // Plain format has dashes as the column separator + no markdown pipes
        #expect(rendered.contains("---"))
        #expect(!rendered.contains("|"))
        #expect(rendered.contains("Cardinality"))
        #expect(rendered.contains("Overall"))
    }

    @Test func emptySourcesRendersNoneSentinel() {
        let report = InteractionDecisionsAggregator.aggregate(.empty)
        let rendered = InteractionMetricsRenderer.render(
            report,
            sources: [],
            format: .markdown
        )
        #expect(rendered.contains("Sources: (none)"))
    }
}
