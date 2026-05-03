import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M2.4 acceptance — parallel of M1.5's
/// `TestLifterCrossValidationTests` for the commutativity template.
/// Constructs a synthetic project with `Sources/Foo/Merger.swift`
/// (defining `merge(_:_:)` matching `CommutativityTemplate.curatedVerbs`)
/// AND `Tests/FooTests/MergerTests.swift` (containing a symmetry
/// pattern), then asserts the resulting `CommutativityTemplate`
/// Suggestion's score includes the +20 cross-validation signal.
@Suite("TestLifter — commutativity cross-validation lights up +20 end-to-end (M2.4)")
struct TestLifterCommutativityCrossValTests {

    @Test("Discover with merge source + commutative test body lights up +20")
    func endToEndCrossValidation() throws {
        let directory = try makeFixtureDirectory(name: "TestLifterCommutativity")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSourcesMerge(in: directory)
        try writeTestsCommutativeBody(in: directory)

        let liftedArtifacts = try TestLifter.discover(in: directory)
        #expect(liftedArtifacts.liftedSuggestions.count == 1)
        let liftedKeys = liftedArtifacts.crossValidationKeys

        let baseline = try TemplateRegistry.discover(in: directory)
        let baselineCommutativity = try #require(baseline.first { $0.templateName == "commutativity" })
        let baselineTotal = baselineCommutativity.score.total

        let crossValidated = try TemplateRegistry.discover(
            in: directory,
            crossValidationFromTestLifter: liftedKeys
        )
        let lifted = try #require(crossValidated.first { $0.templateName == "commutativity" })
        #expect(lifted.score.total == baselineTotal + 20)
        #expect(lifted.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
        #expect(
            lifted.explainability.whySuggested.contains { $0.contains("Cross-validated by TestLifter") }
        )
    }

    @Test("Discover pipeline (CLI surface) wires TestLifter commutativity automatically")
    func cliPipelineWiresTestLifter() throws {
        let directory = try makeFixtureDirectory(name: "TestLifterCommutativityPipeline")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSourcesMerge(in: directory)
        try writeTestsCommutativeBody(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentCommutativityDiagnostics()
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "commutativity" })
        #expect(lifted.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
    }

    @Test("Test-side commutative body without a matching Sources/ function contributes no spurious +20")
    func testWithoutMatchingSourcePair() throws {
        let directory = try makeFixtureDirectory(name: "TestLifterCommutativityUnmatched")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSourcesMerge(in: directory)
        // Test body uses combine — different callee name, so the keys
        // don't collide with merge.
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest
        @testable import Foo

        final class CombinerTests: XCTestCase {
            func testCommutative() {
                let a: [Int] = [1, 2]
                let b: [Int] = [3, 4]
                XCTAssertEqual(combine(a, b), combine(b, a))
            }
        }
        """.write(
            to: tests.appendingPathComponent("CombinerTests.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentCommutativityDiagnostics()
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "commutativity" })
        #expect(!lifted.score.signals.contains { $0.kind == .crossValidation })
    }

    // MARK: - Fixture helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestLifterCommutativityIT-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writeSourcesMerge(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources").appendingPathComponent("Foo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public func merge(_ a: [Int], _ b: [Int]) -> [Int] {
            return a + b
        }
        """.write(
            to: sources.appendingPathComponent("Merger.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeTestsCommutativeBody(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest
        @testable import Foo

        final class MergerTests: XCTestCase {
            func testCommutative() {
                let a: [Int] = [1, 2]
                let b: [Int] = [3, 4]
                XCTAssertEqual(merge(a, b), merge(b, a))
            }
        }
        """.write(
            to: tests.appendingPathComponent("MergerTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }
}

private struct SilentCommutativityDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_ message: String) {}
}
