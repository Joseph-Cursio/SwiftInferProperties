import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M4.4 acceptance — accepting a lifted-promoted suggestion
/// whose `generator.source == .inferredFromTests` writes a stub whose
/// generator body uses the `Gen<T> { T(...) }` mock-inferred shape
/// instead of the `?.gen()` placeholder, with a "Mock-inferred from N
/// construction sites" provenance comment line above the existing M3.3
/// "Lifted from..." line.
///
/// **Fixture shape:** a single test file with a round-trip test method
/// whose setup region carries a typed `let original: Doc = ...`
/// binding (M4.2 recovers Doc as the type) AND ≥3 construction sites
/// of `Doc(title: "...", count: ...)` across the corpus (M4.3
/// synthesizes a `Gen<Doc>`). The test-only callees `serializeDoc` and
/// `deserializeDoc` have no production-side match (M3.1 FunctionSummary
/// lookup misses).
@Suite("TestLifter — accept-flow mock-inferred generator (M4.4)")
struct LiftedAcceptFlowMockGeneratorTests {

    @Test("Accepted lifted suggestion with .inferredFromTests writes Gen<T> { T(...) } stub body")
    func acceptMockInferredWritesGenBody() throws {
        let directory = try makeFixtureDirectory(name: "AcceptMockInferred")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeMockInferableTestFile(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentMockDiagnostics()
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "round-trip" })
        #expect(lifted.generator.source == .inferredFromTests)
        #expect(lifted.generator.confidence == .low)
        #expect(lifted.mockGenerator?.typeName == "Doc")
        let mockSiteCount = try #require(lifted.mockGenerator?.siteCount)
        #expect(mockSiteCount >= 3)

        let recorded = RecordingMockOutput()
        let scripted = ScriptedMockPromptInput(scriptedLines: ["A"])
        let context = InteractiveTriage.Context(
            prompt: scripted,
            output: recorded,
            diagnostics: SilentMockDiagnosticOutput(),
            outputDirectory: directory,
            dryRun: false
        )
        let outcome = try InteractiveTriage.run(
            suggestions: [lifted],
            existingDecisions: .empty,
            context: context
        )

        // File written + contents check.
        let writtenPath = try #require(outcome.writtenFiles.first)
        let contents = try String(contentsOf: writtenPath, encoding: .utf8)
        // Mock-inferred provenance line is present.
        #expect(contents.contains("Mock-inferred from"))
        #expect(contents.contains("low confidence"))
        #expect(contents.contains("verify the generator covers your domain"))
        // Generator body uses the kit's RawType generators wrapped in
        // a Doc(...) construction — NOT the `?.gen()` placeholder
        // M3.3's unrecovered-type path emits.
        #expect(contents.contains("Doc("), "Mock generator should construct Doc")
        #expect(!contents.contains("?.gen()"), "Mock generator should not fall through to ? sentinel")
    }

    @Test("Mock-inferred siteCount is reflected in the provenance comment")
    func provenanceLineCarriesSiteCount() throws {
        let directory = try makeFixtureDirectory(name: "ProvenanceSiteCount")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeMockInferableTestFile(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentMockDiagnostics()
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "round-trip" })
        let siteCount = try #require(lifted.mockGenerator?.siteCount)

        let recorded = RecordingMockOutput()
        let scripted = ScriptedMockPromptInput(scriptedLines: ["A"])
        let context = InteractiveTriage.Context(
            prompt: scripted,
            output: recorded,
            diagnostics: SilentMockDiagnosticOutput(),
            outputDirectory: directory,
            dryRun: false
        )
        let outcome = try InteractiveTriage.run(
            suggestions: [lifted],
            existingDecisions: .empty,
            context: context
        )
        let writtenPath = try #require(outcome.writtenFiles.first)
        let contents = try String(contentsOf: writtenPath, encoding: .utf8)
        #expect(contents.contains("Mock-inferred from \(siteCount) construction"))
    }

    // MARK: - Fixture

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("MockAcceptFlow-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Test fixture that creates the conditions M4.4 needs: a typed
    /// `let original: Doc = ...` binding (M4.2 annotation recovery
    /// fires), test-only `serializeDoc`/`deserializeDoc` callees that
    /// don't appear in `Sources/` (M3.1 FunctionSummary lookup misses),
    /// and ≥3 `Doc(title:, count:)` construction sites distributed
    /// across multiple test methods (M4.1 record sees ≥3 sites for the
    /// `Doc` type, M4.3 synthesizer fires).
    private func writeMockInferableTestFile(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
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
    }
}

// MARK: - Test doubles

private struct SilentMockDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_ message: String) {}
}

private final class SilentMockDiagnosticOutput: DiagnosticOutput, @unchecked Sendable {
    func writeDiagnostic(_ text: String) {}
}

private final class RecordingMockOutput: DiscoverOutput, @unchecked Sendable {
    private(set) var lines: [String] = []
    var text: String { lines.joined(separator: "\n") }
    func write(_ text: String) {
        lines.append(text)
    }
}

private final class ScriptedMockPromptInput: PromptInput, @unchecked Sendable {
    private var remaining: [String]
    init(scriptedLines: [String]) {
        self.remaining = scriptedLines
    }
    func readLine() -> String? {
        guard !remaining.isEmpty else { return nil }
        return remaining.removeFirst()
    }
}
