import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M2.4 acceptance — parallel of M1.5's
/// `TestLifterCrossValidationTests` for the idempotence template.
/// Constructs a synthetic project with `Sources/Foo/Normalizer.swift`
/// (defining `normalize(_:)` matching `IdempotenceTemplate.curatedVerbs`)
/// AND `Tests/FooTests/NormalizerTests.swift` (containing a
/// double-apply pattern), then asserts the resulting
/// `IdempotenceTemplate` Suggestion's score includes the +20
/// cross-validation signal.
@Suite("TestLifter — idempotence cross-validation lights up +20 end-to-end (M2.4)")
struct TestLifterIdempotenceCrossValTests {

    @Test("Discover with normalize source + idempotent test body lights up +20")
    func endToEndCrossValidation() throws {
        let directory = try makeFixtureDirectory(name: "TestLifterIdempotence")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSourcesNormalize(in: directory)
        try writeTestsIdempotentBody(in: directory)

        let liftedArtifacts = try TestLifter.discover(in: directory)
        #expect(liftedArtifacts.liftedSuggestions.count == 1)
        let liftedKeys = liftedArtifacts.crossValidationKeys

        let baseline = try TemplateRegistry.discover(in: directory)
        let baselineIdempotence = try #require(baseline.first { $0.templateName == "idempotence" })
        let baselineTotal = baselineIdempotence.score.total

        let crossValidated = try TemplateRegistry.discover(
            in: directory,
            crossValidationFromTestLifter: liftedKeys
        )
        let lifted = try #require(crossValidated.first { $0.templateName == "idempotence" })
        #expect(lifted.score.total == baselineTotal + 20)
        #expect(lifted.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
        #expect(
            lifted.explainability.whySuggested.contains { $0.contains("Cross-validated by TestLifter") }
        )
    }

    @Test("Discover pipeline (CLI surface) wires TestLifter idempotence automatically")
    func cliPipelineWiresTestLifter() throws {
        let directory = try makeFixtureDirectory(name: "TestLifterIdempotencePipeline")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSourcesNormalize(in: directory)
        try writeTestsIdempotentBody(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentIdempotenceDiagnostics()
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "idempotence" })
        #expect(lifted.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
    }

    @Test("Test-side idempotent body without a matching Sources/ function contributes no spurious +20")
    func testWithoutMatchingSourcePair() throws {
        let directory = try makeFixtureDirectory(name: "TestLifterIdempotenceUnmatched")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSourcesNormalize(in: directory)
        // Test body uses canonicalize — different callee name, so the
        // keys don't collide with normalize.
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest
        @testable import Foo

        final class CanonicalizerTests: XCTestCase {
            func testIdempotent() {
                let s = "hello"
                let once = canonicalize(s)
                let twice = canonicalize(once)
                XCTAssertEqual(once, twice)
            }
        }
        """.write(
            to: tests.appendingPathComponent("CanonicalizerTests.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentIdempotenceDiagnostics()
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "idempotence" })
        // The test's canonicalize key DOESN'T match the normalize source,
        // so the +20 should NOT fire.
        #expect(!lifted.score.signals.contains { $0.kind == .crossValidation })
    }

    // MARK: - Fixture helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestLifterIdempotenceIT-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writeSourcesNormalize(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources").appendingPathComponent("Foo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public func normalize(_ value: String) -> String {
            return value
        }
        """.write(
            to: sources.appendingPathComponent("Normalizer.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeTestsIdempotentBody(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest
        @testable import Foo

        final class NormalizerTests: XCTestCase {
            func testIdempotent() {
                let s = "hello"
                let once = normalize(s)
                let twice = normalize(once)
                XCTAssertEqual(once, twice)
            }
        }
        """.write(
            to: tests.appendingPathComponent("NormalizerTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }
}

private struct SilentIdempotenceDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_ message: String) {}
}
