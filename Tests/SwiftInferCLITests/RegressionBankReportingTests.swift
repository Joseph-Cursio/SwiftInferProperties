import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `emitRegressionTest`'s guard conflated two outcomes: a template that is not
/// `regressionAutoDerivable` (the normal, expected skip) and one that IS but whose calls
/// fail to resolve.
///
/// The second matters because a survey verdict is a *measurement*, not regression
/// protection — §8.6 makes the point that "81 Proven" is not 81 tests, and banking is what
/// converts one into the other. A bank that quietly declines leaves a refutation unprotected
/// with nothing to notice.
@Suite("Regression banking — a decline that is not the normal skip")
struct RegressionBankReportingTests {

    private func entry(template: String, secondary: String?) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "abc123",
            templateName: template,
            typeName: "Widget",
            score: 70,
            tier: "Likely",
            primaryFunctionName: "encode",
            location: "Widget.swift:1",
            firstSeenAt: "2026-08-09",
            lastSeenAt: "2026-08-09",
            secondaryFunctionName: secondary
        )
    }

    private var detail: DefaultFailDetail {
        DefaultFailDetail(
            trial: 1, input: "x", forwardResult: "a", inverseResult: "b", shrink: nil
        )
    }

    /// **The arm that must stay quiet.** Most templates are not auto-derivable, and a line
    /// on every refutation of one would be noise.
    @Test("a template that cannot auto-derive is skipped silently")
    func nonDerivableTemplateIsSilent() {
        var said: [String] = []
        let url = SwiftInferCommand.Verify.emitRegressionTest(
            entry: entry(template: "predicate", secondary: nil),
            detail: detail,
            packageRoot: URL(fileURLWithPath: NSTemporaryDirectory())
        ) { said.append($0) }
        #expect(url == nil)
        #expect(said.isEmpty, "not auto-derivable is the normal case, not a warning")
    }

    /// `round-trip` IS auto-derivable, and resolution throws `missingPairedFunction` with no
    /// secondary name — so the counterexample goes unbanked for a reportable reason.
    @Test("an auto-derivable template whose calls will not resolve is reported")
    func unresolvableCallsAreReported() {
        var said: [String] = []
        let url = SwiftInferCommand.Verify.emitRegressionTest(
            entry: entry(template: "round-trip", secondary: nil),
            detail: detail,
            packageRoot: URL(fileURLWithPath: NSTemporaryDirectory())
        ) { said.append($0) }
        #expect(url == nil, "still degrades rather than trapping")
        #expect(said.count == 1)
        #expect(said.first?.contains("NOT banked") == true)
        #expect(
            said.first?.contains("nothing will re-check") == true,
            "the consequence is the point: a refutation left unprotected"
        )
    }
}
