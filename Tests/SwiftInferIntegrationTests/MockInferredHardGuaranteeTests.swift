import Foundation
import SwiftInferCLI
import SwiftInferCore
import Testing

/// PRD §16 #1 re-check for M4.4 — accepting a mock-inferred lifted
/// suggestion (`generator.source == .inferredFromTests`) writes ONLY
/// to `Tests/Generated/SwiftInfer/`. Mirrors the M3.3-shaped test in
/// `TestLifterHardGuaranteeTests.swift` but exercises the M4
/// mock-fallback path: the synthesizer must not produce a
/// `mockGenerator.typeName` containing `..`/path-hostile chars that
/// would escape the sandbox via `stubFileName(for:)`.
@Suite("TestLifter — PRD §16 #1 mock-inferred sandbox (M4.4)")
struct MockInferredHardGuaranteeTests {

    @Test("Mock-inferred accept-flow writeouts stay under Tests/Generated/SwiftInfer/")
    func mockInferredAcceptStaysSandboxed() throws {
        let directory = try makeFixtureWithMockInferableTests()
        defer { try? FileManager.default.removeItem(at: directory) }

        let pipeline = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: HGSilentDiagnosticOutput()
        )
        let mockInferred = try #require(pipeline.suggestions.first { suggestion in
            suggestion.generator.source == .inferredFromTests
        })

        let recordedOutput = HGSilentOutput()
        let scripted = HGScriptedPromptInput(scriptedLines: ["A"])
        let context = InteractiveTriage.Context(
            prompt: scripted,
            output: recordedOutput,
            diagnostics: HGSilentDiagnosticOutput(),
            outputDirectory: directory,
            dryRun: false
        )
        let outcome = try InteractiveTriage.run(
            suggestions: [mockInferred],
            existingDecisions: .empty,
            context: context
        )

        let sandboxRoot = directory
            .appendingPathComponent("Tests/Generated/SwiftInfer")
            .standardizedFileURL
            .path
        for written in outcome.writtenFiles {
            let writtenStandardized = written.standardizedFileURL.path
            #expect(
                writtenStandardized.hasPrefix(sandboxRoot + "/"),
                "M4.4 mock-inferred accept-flow writeout escaped Tests/Generated/SwiftInfer/: \(written.path)"
            )
        }
    }

    /// Build a fixture that triggers M4.3's mock-inferred fallback:
    /// test-only callees + ≥3 typed `let original: Doc = Doc(...)`
    /// bindings across multiple test methods.
    private func makeFixtureWithMockInferableTests() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInferM44HG-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let tests = base.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest

        final class FooTests: XCTestCase {
            func testRoundTrip() {
                let original: Doc = Doc(title: "alpha", count: 1)
                let serialized = serializeDoc(original)
                let deserialized = deserializeDoc(serialized)
                XCTAssertEqual(original, deserialized)
            }
            func testFixtureA() {
                let a = Doc(title: "beta", count: 2)
                XCTAssertNotNil(a)
            }
            func testFixtureB() {
                let b = Doc(title: "gamma", count: 3)
                XCTAssertNotNil(b)
            }
        }
        """.write(
            to: tests.appendingPathComponent("FooTests.swift"),
            atomically: true,
            encoding: .utf8
        )
        return base
    }
}
