import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M5.6 acceptance — parallel of M2.4's idempotence
/// cross-validation test for the count-invariance template. Constructs
/// a synthetic project with `Sources/Foo/Filter.swift` (defining
/// `filter(_:)` annotated with `@CheckProperty(.preservesInvariant(\.count))`
/// — the annotation-only premise of `InvariantPreservationTemplate`)
/// AND `Tests/FooTests/FilterTests.swift` (containing the M5.2
/// count-invariance shape), then asserts the resulting
/// `InvariantPreservationTemplate` Suggestion's score includes the +20
/// cross-validation signal.
@Suite("TestLifter — count-invariance cross-validation lights up +20 end-to-end (M5.6)")
struct TestLifterCountInvarianceCrossValTests {

    @Test("Discover with annotated filter source + count-preserving test body lights up +20")
    func endToEndCrossValidation() throws {
        let directory = try makeFixtureDirectory(name: "TestLifterCountInvariance")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSourcesAnnotatedFilter(in: directory)
        try writeTestsCountInvariantBody(in: directory)

        let liftedArtifacts = try TestLifter.discover(in: directory)
        let liftedKeys = liftedArtifacts.crossValidationKeys
        #expect(liftedKeys.contains(
            CrossValidationKey(templateName: "invariant-preservation", calleeNames: ["filter"])
        ))

        let baseline = try TemplateRegistry.discover(in: directory)
        let baselineSuggestion = try #require(
            baseline.first { $0.templateName == "invariant-preservation" }
        )
        let baselineTotal = baselineSuggestion.score.total

        let crossValidated = try TemplateRegistry.discover(
            in: directory,
            crossValidationFromTestLifter: liftedKeys
        )
        let lifted = try #require(crossValidated.first { $0.templateName == "invariant-preservation" })
        #expect(lifted.score.total == baselineTotal + 20)
        #expect(lifted.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
        #expect(
            lifted.explainability.whySuggested.contains { $0.contains("Cross-validated by TestLifter") }
        )
    }

    @Test("Discover pipeline (CLI surface) wires TestLifter count-invariance automatically")
    func cliPipelineWiresTestLifter() throws {
        let directory = try makeFixtureDirectory(name: "TestLifterCountInvariancePipeline")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSourcesAnnotatedFilter(in: directory)
        try writeTestsCountInvariantBody(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentCountInvarianceDiagnostics()
        )
        let lifted = try #require(
            result.suggestions.first { $0.templateName == "invariant-preservation" }
        )
        #expect(lifted.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
    }

    // MARK: - Fixture helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestLifterCountInvarianceIT-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writeSourcesAnnotatedFilter(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources").appendingPathComponent("Foo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        @CheckProperty(.preservesInvariant(\\.count))
        public func filter(_ xs: [Int]) -> [Int] {
            return xs
        }
        """.write(
            to: sources.appendingPathComponent("Filter.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeTestsCountInvariantBody(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest
        @testable import Foo

        final class FilterTests: XCTestCase {
            func testFilterPreservesCount() {
                let xs = [1, 2, 3, 4]
                XCTAssertEqual(filter(xs).count, xs.count)
            }
        }
        """.write(
            to: tests.appendingPathComponent("FilterTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }
}

private struct SilentCountInvarianceDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_ message: String) {}
}
