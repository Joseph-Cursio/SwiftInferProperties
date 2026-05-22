import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M14.2 — companion to `EquivalenceClassRenderingNClassTests`.
/// Covers the partial-coverage path of the M14 axis-4 exhaustiveness
/// rule end-to-end: a `Size` enum with four cases vs a vocabulary
/// marker set naming only three drops `coversDomain` to `false` and
/// suppresses the `Exhaustiveness:` comment from the writeout. Split
/// out of the main file at M14.2 to keep that struct under SwiftLint's
/// `type_body_length` cap.
@Suite("TestLifter — accept-flow N-class coversDomain partial coverage (M14.2)")
struct ECNClassPartialCoverageTests {

    @Test("Three-class corpus with markerSet missing one case → coversDomain false → no exhaustiveness")
    func acceptNClassPartialCoverage() throws {
        let directory = try makeFixtureDirectory(name: "PartialCoverage")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePartialCoverageSizerFixture(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentECNCDiagnostics()
        )
        let advisory = try #require(result.suggestions.first { $0.templateName == "equivalence-class" })
        let kind = try #require(result.equivalenceClassHintsByIdentity[advisory.identity])
        guard case .nClass(let hint) = kind else {
            Issue.record("expected N-class hint kind, got \(kind)"); return
        }
        // The Size enum has four cases (small/medium/large/extraLarge);
        // the markerSet covers only three. Partition isn't exhaustive.
        #expect(hint.coversDomain == false)

        let recorded = RecordingECNCOutput()
        let scripted = ScriptedECNCPromptInput(scriptedLines: ["A"])
        let context = InteractiveTriage.Context(
            prompt: scripted, output: recorded,
            diagnostics: SilentECNCDiagnosticOutput(),
            outputDirectory: directory, dryRun: false,
            equivalenceClassHintsByIdentity: result.equivalenceClassHintsByIdentity
        )
        let outcome = try InteractiveTriage.run(
            suggestions: [advisory], existingDecisions: .empty, context: context
        )
        let writtenPath = try #require(outcome.writtenFiles.first)
        let contents = try String(contentsOf: writtenPath, encoding: .utf8)
        #expect(!contents.contains("Exhaustiveness:"))
    }

    // MARK: - Fixtures

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ECNClassPartialCoverage-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writePartialCoverageSizerFixture(in directory: URL) throws {
        try writePartialSizerSource(in: directory)
        try writePartialSizerVocabulary(in: directory)
        try writePartialSizerTests(in: directory)
    }

    private func writePartialSizerSource(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources").appendingPathComponent("Foo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public enum Size: Equatable {
            case small, medium, large, extraLarge
        }

        public func size(_ box: Box) -> Size {
            switch box.count {
            case 0..<10: return .small
            case 10..<100: return .medium
            case 100..<1000: return .large
            default: return .extraLarge
            }
        }

        public struct Box: Equatable {
            public let count: Int
            public init(count: Int) { self.count = count }
        }
        """.write(to: sources.appendingPathComponent("Sizer.swift"), atomically: true, encoding: .utf8)
    }

    private func writePartialSizerVocabulary(in directory: URL) throws {
        let configDir = directory.appendingPathComponent(".swiftinfer")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try """
        {
          "markerSets": [
            { "name": "Sizes", "markers": ["Small", "Medium", "Large"] }
          ]
        }
        """.write(
            to: configDir.appendingPathComponent("vocabulary.json"),
            atomically: true, encoding: .utf8
        )
        try "// swift-tools-version: 6.1\n".write(
            to: directory.appendingPathComponent("Package.swift"),
            atomically: true, encoding: .utf8
        )
    }

    private func writePartialSizerTests(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest

        final class SizerTests: XCTestCase {
            func testSmall_a() { XCTAssertEqual(size("abc"), .small) }
            func testSmall_b() { XCTAssertEqual(size("def"), .small) }
            func testSmall_c() { XCTAssertEqual(size("ghi"), .small) }
            func testMedium_a() { XCTAssertEqual(size(String(repeating: "x", count: 30)), .medium) }
            func testMedium_b() { XCTAssertEqual(size(String(repeating: "y", count: 50)), .medium) }
            func testMedium_c() { XCTAssertEqual(size(String(repeating: "z", count: 70)), .medium) }
            func testLarge_a() { XCTAssertEqual(size(String(repeating: "p", count: 200)), .large) }
            func testLarge_b() { XCTAssertEqual(size(String(repeating: "q", count: 300)), .large) }
            func testLarge_c() { XCTAssertEqual(size(String(repeating: "r", count: 400)), .large) }
        }
        """.write(
            to: tests.appendingPathComponent("SizerTests.swift"),
            atomically: true, encoding: .utf8
        )
    }
}

// MARK: - Test doubles

private struct SilentECNCDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_ message: String) {}
}

private final class SilentECNCDiagnosticOutput: DiagnosticOutput, @unchecked Sendable {
    func writeDiagnostic(_ text: String) {}
}

private final class RecordingECNCOutput: DiscoverOutput, @unchecked Sendable {
    private(set) var lines: [String] = []
    var text: String { lines.joined(separator: "\n") }

    func write(_ text: String) {
        lines.append(text)
    }
}

private final class ScriptedECNCPromptInput: PromptInput, @unchecked Sendable {
    private var remaining: [String]

    init(scriptedLines: [String]) {
        self.remaining = scriptedLines
    }
    func readLine() -> String? {
        guard !remaining.isEmpty else { return nil }
        return remaining.removeFirst()
    }
}
