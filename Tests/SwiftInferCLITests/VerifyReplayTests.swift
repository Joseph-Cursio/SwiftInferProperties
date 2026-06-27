import Testing

@testable import SwiftInferCLI

/// V1.143.B — pure replay-report tests. The subprocess re-verify path is
/// exercised by the integration suite; here we pin the classification, the
/// CI-gate predicate, and the rendered summary.
@Suite("Verify replay report — V1.143.B")
struct VerifyReplayTests {

    @Test("outcome → status mapping")
    func statusMapping() {
        #expect(ReplayReport.status(for: .measuredDefaultFails) == .stillFailing)
        #expect(ReplayReport.status(for: .measuredBothPass) == .nowHolds)
        #expect(ReplayReport.status(for: .measuredEdgeCaseAdvisory) == .nowHolds)
        #expect(ReplayReport.status(for: .measuredError) == .inconclusive)
        #expect(ReplayReport.status(for: .architecturalCoveragePending) == .inconclusive)
    }

    private func line(_ id: String, _ status: ReplayReport.Status) -> ReplayReport.Line {
        ReplayReport.Line(identityHash: id, template: "idempotence", status: status, detail: nil)
    }

    @Test("hasRegressions is true iff any recorded counterexample still fails")
    func gatePredicate() {
        let clean = ReplayReport(lines: [line("A", .nowHolds), line("B", .skipped)])
        #expect(clean.hasRegressions == false)

        let regressed = ReplayReport(lines: [line("A", .nowHolds), line("B", .stillFailing)])
        #expect(regressed.hasRegressions)
        #expect(regressed.count(.stillFailing) == 1)
        #expect(regressed.count(.nowHolds) == 1)
    }

    @Test("render summarizes counts and one line per entry with status glyphs")
    func renderSummary() {
        let report = ReplayReport(lines: [
            line("AAAA", .nowHolds),
            line("BBBB", .stillFailing),
            line("CCCC", .skipped)
        ])
        let rendered = report.render()
        #expect(rendered.contains("3 recorded counterexample(s)"))
        #expect(rendered.contains("now holds: 1"))
        #expect(rendered.contains("still failing: 1"))
        #expect(rendered.contains("skipped: 1"))
        #expect(rendered.contains("✓ AAAA"))
        #expect(rendered.contains("✗ BBBB"))
        #expect(rendered.contains("– CCCC"))
    }
}
