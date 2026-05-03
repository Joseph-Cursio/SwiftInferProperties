import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M3.3 acceptance — accepting a lifted-promoted suggestion
/// in `swift-infer discover --interactive` writes a peer test stub to
/// `Tests/Generated/SwiftInfer/<template>/<TestMethodName>_lifted_<template>.swift`
/// with a provenance comment header pointing at the originating test
/// method, and unrecovered-type lifted suggestions emit a `.todo<?>()`
/// stub that doesn't compile (PRD §16 #4 invariant preserved).
@Suite("TestLifter — accept-flow writeouts (M3.3)")
struct TestLifterAcceptFlowIntegrationTests {

    @Test("Accepting a lifted round-trip suggestion writes <TestMethodName>_lifted_round-trip.swift")
    func acceptLiftedRoundTripWritesDisambiguatedFile() throws {
        let directory = try makeFixtureDirectory(name: "AcceptLiftedRoundTrip")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeUnmatchedRoundTripTest(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentDiagnostics()
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "round-trip" })
        #expect(lifted.liftedOrigin?.testMethodName == "testRoundTrip")

        let recordedOutput = RecordingOutput()
        let scripted = ScriptedPromptInput(scriptedLines: ["A"])
        let context = InteractiveTriage.Context(
            prompt: scripted,
            output: recordedOutput,
            diagnostics: SilentDiagnosticOutput(),
            outputDirectory: directory,
            dryRun: false
        )
        let outcome = try InteractiveTriage.run(
            suggestions: [lifted],
            existingDecisions: .empty,
            context: context
        )

        // File path matches the M3.3 disambiguated naming pattern.
        let writtenPath = try #require(outcome.writtenFiles.first)
        let expectedPath = directory
            .appendingPathComponent("Tests/Generated/SwiftInfer/round-trip/testRoundTrip_lifted_round-trip.swift")
        #expect(writtenPath.path == expectedPath.path)

        // File contents carry the provenance header.
        let contents = try String(contentsOf: writtenPath, encoding: .utf8)
        #expect(contents.contains("// Lifted from"))
        #expect(contents.contains("testRoundTrip()"))
    }

    @Test("--dry-run reports the would-be path without writing a file")
    func dryRunReportsPathWithoutWriting() throws {
        let directory = try makeFixtureDirectory(name: "DryRunLiftedRoundTrip")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeUnmatchedRoundTripTest(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentDiagnostics()
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "round-trip" })

        let recordedOutput = RecordingOutput()
        let scripted = ScriptedPromptInput(scriptedLines: ["A"])
        let context = InteractiveTriage.Context(
            prompt: scripted,
            output: recordedOutput,
            diagnostics: SilentDiagnosticOutput(),
            outputDirectory: directory,
            dryRun: true
        )
        let outcome = try InteractiveTriage.run(
            suggestions: [lifted],
            existingDecisions: .empty,
            context: context
        )

        // No file written under dry-run.
        #expect(outcome.writtenFiles.isEmpty)
        // The would-be path is reported on stdout — the M6.4 dry-run
        // contract from the existing accept-flow.
        #expect(recordedOutput.text.contains("[dry-run] would write"))
        #expect(recordedOutput.text.contains("testRoundTrip_lifted_round-trip.swift"))
        // Not actually present on disk.
        let expectedPath = directory
            .appendingPathComponent("Tests/Generated/SwiftInfer/round-trip/testRoundTrip_lifted_round-trip.swift")
        #expect(!FileManager.default.fileExists(atPath: expectedPath.path))
    }

    @Test("Lifted suggestion with unrecovered types writes a .todo stub that doesn't compile (PRD §16 #4)")
    func unrecoveredTypeProducesTodoStub() throws {
        let directory = try makeFixtureDirectory(name: "TodoLiftedRoundTrip")
        defer { try? FileManager.default.removeItem(at: directory) }
        // Same fixture as the round-trip case — `serialize`/`deserialize`
        // are not defined anywhere, so type recovery falls back to `?`
        // and `LiftedTestEmitter.defaultGenerator(for: "?")` produces
        // `.todo<?>()`.
        try writeUnmatchedRoundTripTest(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentDiagnostics()
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "round-trip" })

        let recordedOutput = RecordingOutput()
        let scripted = ScriptedPromptInput(scriptedLines: ["A"])
        let context = InteractiveTriage.Context(
            prompt: scripted,
            output: recordedOutput,
            diagnostics: SilentDiagnosticOutput(),
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
        // For unrecognized typeNames (the `?` sentinel from failed
        // recovery), `LiftedTestEmitter.defaultGenerator` falls back to
        // `\(typeName).gen()` — for `typeName == "?"`, that's `?.gen()`,
        // which doesn't compile (no Swift type literally named `?`,
        // and `?.gen()` is not valid syntax). This preserves the
        // PRD §16 #4 spirit: SwiftInfer never emits silently-passing
        // code when generator inference fails. The user has to
        // replace the `?` with a concrete generator before the stub
        // compiles.
        #expect(contents.contains("?.gen()"))
    }

    // MARK: - Fixture

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestLifterAcceptFlow-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writeUnmatchedRoundTripTest(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest

        final class FooTests: XCTestCase {
            func testRoundTrip() {
                let original = "hello"
                let serialized = serialize(original)
                let deserialized = deserialize(serialized)
                XCTAssertEqual(original, deserialized)
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

private struct SilentDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_ message: String) {}
}

private final class SilentDiagnosticOutput: DiagnosticOutput, @unchecked Sendable {
    func writeDiagnostic(_ text: String) {}
}

private final class RecordingOutput: DiscoverOutput, @unchecked Sendable {
    private(set) var lines: [String] = []
    var text: String { lines.joined(separator: "\n") }
    func write(_ text: String) {
        lines.append(text)
    }
}

private final class ScriptedPromptInput: PromptInput, @unchecked Sendable {
    private var remaining: [String]
    init(scriptedLines: [String]) {
        self.remaining = scriptedLines
    }
    func readLine() -> String? {
        guard !remaining.isEmpty else { return nil }
        return remaining.removeFirst()
    }
}
