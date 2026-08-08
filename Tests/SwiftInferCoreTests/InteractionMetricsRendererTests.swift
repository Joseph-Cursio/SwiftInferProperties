import Foundation
@testable import SwiftInferCore
import Testing

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

    /// The threshold is **exclusive**, and nothing pinned that until a mutation sweep
    /// asked.
    ///
    /// `docs/measurements/mutation-sweep-slice1-findings.md`: `skipRate > threshold`
    /// mutated to `>=` was the sweep's only survivor. The two differ solely at exactly
    /// 0.30, and the existing coverage sits at 80% — its own comment says "well above 30%
    /// threshold" — so no test could tell the two apart.
    ///
    /// **3 skipped of 10 is the witness**, and it is exact rather than approximate:
    /// `3.0 / 10.0` and the literal `0.30` round to the same `Double`, so the comparison
    /// really does land on the boundary rather than near it. A footnote here would mean
    /// the renderer flags a family that merely *reaches* the refinement threshold instead
    /// of exceeding it.
    @Test func skipRateExactlyAtThresholdIsNotFlagged() {
        // 3 skipped / 10 total = 0.30 exactly — the boundary, not beyond it.
        var records = [
            record(identity: "A", family: .biconditional, decision: .skipped),
            record(identity: "B", family: .biconditional, decision: .skipped),
            record(identity: "C", family: .biconditional, decision: .skipped)
        ]
        for name in ["D", "E", "F", "G", "H", "I", "J"] {
            records.append(record(identity: name, family: .biconditional, decision: .accepted))
        }
        let report = InteractionDecisionsAggregator.aggregate(InteractionDecisions(records: records))
        let rendered = InteractionMetricsRenderer.render(
            report,
            sources: ["test"],
            format: .markdown
        )
        #expect(rendered.contains("| 30% |"), "the rate itself should still render")
        // The footnote is what `anyFamilyExceedsSkipThreshold` drives, so it is the
        // assertion that separates `>` from `>=`. Asserting on the row's asterisk instead
        // does NOT: the overall row renders `**30%**`, and `"30%*"` matches the markdown
        // bold delimiter — a false positive that made the first version of this test fail
        // against correct code.
        #expect(!rendered.contains("refinement threshold"), "at the threshold exactly, no footnote")
        #expect(!rendered.contains("| 30%* |"), "and no flag on the row")
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

    /// Completeness guard — `familyDisplayOrder` decouples the per-family
    /// metrics table from `InteractionInvariantFamily`'s case-declaration
    /// order, but an explicit array isn't compiler-checked for coverage.
    /// A family added to the enum but not to `familyDisplayOrder` would
    /// silently vanish from the rendered table; this catches that.
    @Test("familyDisplayOrder covers every InteractionInvariantFamily case")
    func familyDisplayOrderIsExhaustive() {
        #expect(
            Set(InteractionMetricsRenderer.familyDisplayOrder)
                == Set(InteractionInvariantFamily.allCases)
        )
    }
}
