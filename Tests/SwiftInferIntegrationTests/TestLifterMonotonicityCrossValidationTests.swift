import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M5.6 acceptance — parallel of M2.4's
/// `TestLifterIdempotenceCrossValidationTests` for the monotonicity
/// template. Constructs a synthetic project with `Sources/Foo/Pricing.swift`
/// (defining `applyDiscount(_:)` whose `(Int) -> Int` codomain matches
/// `MonotonicityTemplate`'s curated comparable set) AND
/// `Tests/FooTests/PricingTests.swift` (containing the M5.1 monotonicity
/// shape), then asserts the resulting `MonotonicityTemplate` Suggestion's
/// score includes the +20 cross-validation signal.
@Suite("TestLifter — monotonicity cross-validation lights up +20 end-to-end (M5.6)")
struct TestLifterMonotonicityCrossValTests {

    @Test("Discover with applyDiscount source + monotonic test body lights up +20")
    func endToEndCrossValidation() throws {
        let directory = try makeFixtureDirectory(name: "TestLifterMonotonicity")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSourcesApplyDiscount(in: directory)
        try writeTestsMonotonicBody(in: directory)

        let liftedArtifacts = try TestLifter.discover(in: directory)
        let liftedKeys = liftedArtifacts.crossValidationKeys
        #expect(liftedKeys.contains(
            CrossValidationKey(templateName: "monotonicity", calleeNames: ["applyDiscount"])
        ))

        let baseline = try TemplateRegistry.discover(in: directory)
        let baselineMonotonic = try #require(baseline.first { $0.templateName == "monotonicity" })
        let baselineTotal = baselineMonotonic.score.total

        let crossValidated = try TemplateRegistry.discover(
            in: directory,
            crossValidationFromTestLifter: liftedKeys
        )
        let lifted = try #require(crossValidated.first { $0.templateName == "monotonicity" })
        #expect(lifted.score.total == baselineTotal + 20)
        #expect(lifted.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
        #expect(
            lifted.explainability.whySuggested.contains { $0.contains("Cross-validated by TestLifter") }
        )
    }

    @Test("Discover pipeline (CLI surface) wires TestLifter monotonicity automatically")
    func cliPipelineWiresTestLifter() throws {
        let directory = try makeFixtureDirectory(name: "TestLifterMonotonicityPipeline")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSourcesApplyDiscount(in: directory)
        try writeTestsMonotonicBody(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentMonotonicityDiagnostics()
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "monotonicity" })
        #expect(lifted.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
    }

    // MARK: - Fixture helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestLifterMonotonicityIT-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writeSourcesApplyDiscount(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources").appendingPathComponent("Foo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public func applyDiscount(_ price: Int) -> Int {
            return price - 1
        }
        """.write(
            to: sources.appendingPathComponent("Pricing.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeTestsMonotonicBody(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest
        @testable import Foo

        final class PricingTests: XCTestCase {
            func testApplyDiscountIsMonotonic() {
                let a = 5
                let b = 10
                XCTAssertLessThan(a, b)
                XCTAssertLessThanOrEqual(applyDiscount(a), applyDiscount(b))
            }
        }
        """.write(
            to: tests.appendingPathComponent("PricingTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }
}

private struct SilentMonotonicityDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_ message: String) {}
}
