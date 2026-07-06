import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Slice 5a fast tests for the `verify-value-semantics` report renderer + the
/// `--fail-on-leak` gate. Pure inputs; no subprocess.
struct ValueSemanticVerifyReportTests {

    private func result(
        _ name: String,
        line: Int = 1,
        _ status: ValueSemanticVerifyResult.Status
    ) -> ValueSemanticVerifyResult {
        ValueSemanticVerifyResult(
            typeName: name,
            location: SourceLocation(file: "Sources/M/\(name).swift", line: line, column: 1),
            status: status
        )
    }

    @Test func emptyResultsReportsNoCandidates() {
        let out = ValueSemanticVerifyReport.render(results: [], moduleName: "MyKit")
        #expect(out == "swift-infer verify-value-semantics: no value-semantics candidates found in MyKit.\n")
    }

    @Test func groupsByStatusWithLeaksLeadingAndRepro() {
        let out = ValueSemanticVerifyReport.render(
            results: [
                result("SafeStore", .verifiedSafe),
                result("LeakyStore", .confirmedLeak(repro: "LeakyStore leaks: copy, then addOne")),
                result("Inventory", .notVerifiable(reason: "not Equatable")),
                result("Broken", .buildFailed(detail: "error: no such module"))
            ],
            moduleName: "MyKit"
        )
        #expect(out.contains("CONFIRMED LEAKS (1)"))
        #expect(out.contains("LeakyStore leaks: copy, then addOne"))
        #expect(out.contains("Verified value-semantic (1)"))
        #expect(out.contains("Not verifiable (1)"))
        #expect(out.contains("Inventory — not Equatable"))
        #expect(out.contains("Build / verify errors (1)"))
        #expect(out.contains("Broken — error: no such module"))
        let summary = "Summary: 4 candidates \u{00B7} 1 leak \u{00B7} 1 safe \u{00B7} 1 skipped \u{00B7} 1 error"
        #expect(out.contains(summary))
        // Polarity: leaks lead the report.
        let leakIndex = try? #require(out.range(of: "CONFIRMED LEAKS")).lowerBound
        let safeIndex = try? #require(out.range(of: "Verified value-semantic")).lowerBound
        #expect(leakIndex != nil && safeIndex != nil && leakIndex! < safeIndex!)
    }

    @Test func pluralizationAndErrorsOmittedWhenZero() {
        let out = ValueSemanticVerifyReport.render(
            results: [
                result("A", .verifiedSafe),
                result("B", .verifiedSafe)
            ],
            moduleName: "M"
        )
        #expect(out.contains("Summary: 2 candidates \u{00B7} 0 leaks \u{00B7} 2 safe \u{00B7} 0 skipped"))
        #expect(!out.contains("error"))
        #expect(!out.contains("CONFIRMED LEAKS"))
    }

    @Test func sortsDeterministicallyWithinGroup() {
        let out = ValueSemanticVerifyReport.render(
            results: [
                result("Zebra", line: 9, .verifiedSafe),
                result("Apple", line: 3, .verifiedSafe)
            ],
            moduleName: "M"
        )
        let appleIndex = out.range(of: "Apple")!.lowerBound
        let zebraIndex = out.range(of: "Zebra")!.lowerBound
        #expect(appleIndex < zebraIndex)
    }

    @Test func leaksFoundDrivesTheGate() {
        #expect(ValueSemanticVerifyReport.leaksFound(in: [result("A", .verifiedSafe)]) == false)
        #expect(ValueSemanticVerifyReport.leaksFound(in: [
            result("A", .verifiedSafe),
            result("B", .confirmedLeak(repro: "x"))
        ]))
    }
}
