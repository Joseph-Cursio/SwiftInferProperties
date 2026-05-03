import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M5.6 acceptance — parallel of M2.4's idempotence
/// cross-validation test for the associativity template. Constructs
/// a synthetic project with `Sources/Foo/Combine.swift` (defining
/// `combine(_:_:)` whose `(T, T) -> T` shape + curated-verb name match
/// AssociativityTemplate's surface) AND `Tests/FooTests/CombineTests.swift`
/// (containing the M5.3 reduce-equivalence shape), then asserts the
/// resulting `AssociativityTemplate` Suggestion's score includes the
/// +20 cross-validation signal.
@Suite("TestLifter — associativity cross-validation lights up +20 end-to-end (M5.6)")
struct TestLifterAssociativityCrossValTests {

    @Test("Discover with combine source + reduce-equivalence test body lights up +20")
    func endToEndCrossValidation() throws {
        let directory = try makeFixtureDirectory(name: "TestLifterAssociativity")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSourcesCombine(in: directory)
        try writeTestsReduceEquivalentBody(in: directory)

        let liftedArtifacts = try TestLifter.discover(in: directory)
        let liftedKeys = liftedArtifacts.crossValidationKeys
        #expect(liftedKeys.contains(
            CrossValidationKey(templateName: "associativity", calleeNames: ["combine"])
        ))

        let baseline = try TemplateRegistry.discover(in: directory)
        let baselineSuggestion = try #require(baseline.first { $0.templateName == "associativity" })
        let baselineTotal = baselineSuggestion.score.total

        let crossValidated = try TemplateRegistry.discover(
            in: directory,
            crossValidationFromTestLifter: liftedKeys
        )
        let lifted = try #require(crossValidated.first { $0.templateName == "associativity" })
        #expect(lifted.score.total == baselineTotal + 20)
        #expect(lifted.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
        #expect(
            lifted.explainability.whySuggested.contains { $0.contains("Cross-validated by TestLifter") }
        )
    }

    @Test("Discover pipeline (CLI surface) wires TestLifter associativity automatically")
    func cliPipelineWiresTestLifter() throws {
        let directory = try makeFixtureDirectory(name: "TestLifterAssociativityPipeline")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSourcesCombine(in: directory)
        try writeTestsReduceEquivalentBody(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentAssociativityDiagnostics()
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "associativity" })
        #expect(lifted.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
    }

    // MARK: - Fixture helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestLifterAssociativityIT-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writeSourcesCombine(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources").appendingPathComponent("Foo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public func combine(_ lhs: Int, _ rhs: Int) -> Int {
            return lhs + rhs
        }
        """.write(
            to: sources.appendingPathComponent("Combine.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeTestsReduceEquivalentBody(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest
        @testable import Foo

        final class CombineTests: XCTestCase {
            func testCombineReduceIsReversalInvariant() {
                let xs = [1, 2, 3]
                XCTAssertEqual(xs.reduce(0, combine), xs.reversed().reduce(0, combine))
            }
        }
        """.write(
            to: tests.appendingPathComponent("CombineTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }
}

private struct SilentAssociativityDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_ message: String) {}
}
