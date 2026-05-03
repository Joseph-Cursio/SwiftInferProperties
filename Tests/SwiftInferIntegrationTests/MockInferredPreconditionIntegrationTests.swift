import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M9.3 — end-to-end integration test verifying that
/// `// Inferred precondition:` provenance comment lines surface in
/// the writeout of an accepted lifted suggestion when the M4.1
/// construction record carries patterns the M9.1 inferrer recognizes.
///
/// **Fixture shape:** mirrors `LiftedAcceptFlowMockGeneratorTests`'s
/// round-trip fixture but tightens the construction-site literals so
/// (a) every `count` value is a distinct positive Int (`1`, `2`, `3`,
/// `4`, `5`) → `.intRange(low: 1, high: 5)` per OD #4 most-specific
/// rule; (b) every `title` value is a distinct non-empty String of
/// varying length → `.stringLength(low: 4, high: 7)`. The accept-flow
/// stub for the resulting Doc round-trip suggestion should carry
/// per-position `// Inferred precondition:` comments inside its
/// `Gen<Doc>` expression.
@Suite("TestLifter — accept-flow precondition rendering integration (M9.3)")
struct MockInferredPreconditionIntegrationTests {

    @Test("Accept of mock-inferred lifted suggestion writes per-position precondition hint comments")
    func acceptMockInferredWritesPreconditionHintLines() throws {
        let directory = try makeFixtureDirectory(name: "AcceptMockPreconditions")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePreconditionFixtureFile(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentPreconditionDiagnostics()
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "round-trip" })
        #expect(lifted.generator.source == .inferredFromTests)
        let mock = try #require(lifted.mockGenerator)
        // Synthesizer should have produced two hints (one per arg
        // position) — count is positive distinct ints, title is
        // non-empty distinct lengths.
        #expect(mock.preconditionHints.count == 2)

        let recorded = RecordingPreconditionOutput()
        let scripted = ScriptedPreconditionPromptInput(scriptedLines: ["A"])
        let context = InteractiveTriage.Context(
            prompt: scripted,
            output: recorded,
            diagnostics: SilentPreconditionDiagnosticOutput(),
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
        // The two hints surface as comment lines inside the Gen<Doc>
        // expression. Both arguments named in the comments.
        let hintLines = contents.components(separatedBy: "\n")
            .filter { $0.contains("// Inferred precondition:") }
        #expect(hintLines.count == 2, "expected 2 hint comment lines, got \(hintLines.count): \(hintLines)")
        #expect(contents.contains("count — all observed values are in [1, 5]"))
        // Title strings: "alpha"(5) "betas"(5) "gammas"(6) "deltas!"(7) "epsilon"(7)
        // → distinct lengths {5, 6, 7} → .stringLength(low: 5, high: 7).
        #expect(contents.contains("title — all observed strings have length in [5, 7]"))
        // M4.4 mock-inferred provenance line is still present.
        #expect(contents.contains("Mock-inferred from"))
    }

    @Test("No precondition hints renders without comment lines (regression for M4.4 baseline)")
    func acceptMockWithoutPatternsHasNoHintLines() throws {
        let directory = try makeFixtureDirectory(name: "AcceptMockNoHints")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeNonPatternFixtureFile(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentPreconditionDiagnostics()
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "round-trip" })
        let mock = try #require(lifted.mockGenerator)
        // Mixed-bool flag → no hint can fire on that position. Title
        // length is single-distinct → no stringLength; all-non-empty
        // gets nonEmptyString hint though. So expect 1 hint.
        #expect(mock.preconditionHints.count == 1)

        let recorded = RecordingPreconditionOutput()
        let scripted = ScriptedPreconditionPromptInput(scriptedLines: ["A"])
        let context = InteractiveTriage.Context(
            prompt: scripted,
            output: recorded,
            diagnostics: SilentPreconditionDiagnosticOutput(),
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
        let hintLines = contents.components(separatedBy: "\n")
            .filter { $0.contains("// Inferred precondition:") }
        // Only the title arg produces a hint; the flag arg's mixed
        // booleans kill its hint per the conservative bias.
        #expect(hintLines.count == 1)
        #expect(contents.contains("title — all observed strings are non-empty"))
        #expect(!contents.contains("flag —"))
    }

    // MARK: - Fixtures

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("MockPreconditions-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Round-trip fixture with five Doc(title:, count:) construction
    /// sites where both arguments hit a curated pattern: count is a
    /// distinct positive int range [1, 5]; title is a distinct
    /// non-empty string range with lengths [4, 5, 6, 7] (4 distinct
    /// lengths from "abcd" / "abcde" / "abcdef" / "abcdefg" — actually
    /// using "alpha" / "betas" / "gamma" / "delta" / "epsilon" gives
    /// distinct lengths in [4, 7]).
    private func writePreconditionFixtureFile(in directory: URL) throws {
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
                let a = Doc(title: "betas", count: 2)
                XCTAssertNotNil(a)
            }

            func testFixtureB() {
                let b = Doc(title: "gammas", count: 3)
                XCTAssertNotNil(b)
            }

            func testFixtureC() {
                let c = Doc(title: "deltas!", count: 4)
                XCTAssertNotNil(c)
            }

            func testFixtureD() {
                let d = Doc(title: "epsilon", count: 5)
                XCTAssertNotNil(d)
            }
        }
        """.write(
            to: tests.appendingPathComponent("FooTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// Fixture where one argument hits a pattern (title — all
    /// non-empty, single distinct length 5) but another doesn't
    /// (flag — mixed true/false).
    private func writeNonPatternFixtureFile(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest

        final class FooTests: XCTestCase {
            func testRoundTrip() {
                let original: Doc = Doc(title: "alpha", flag: true)
                let serialized = serializeDoc(original)
                let deserialized = deserializeDoc(serialized)
                XCTAssertEqual(original, deserialized)
            }

            func testFixtureA() {
                let a = Doc(title: "betas", flag: false)
                XCTAssertNotNil(a)
            }

            func testFixtureB() {
                let b = Doc(title: "gamma", flag: true)
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

private struct SilentPreconditionDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_ message: String) {}
}

private final class SilentPreconditionDiagnosticOutput: DiagnosticOutput, @unchecked Sendable {
    func writeDiagnostic(_ text: String) {}
}

private final class RecordingPreconditionOutput: DiscoverOutput, @unchecked Sendable {
    private(set) var lines: [String] = []
    var text: String { lines.joined(separator: "\n") }
    func write(_ text: String) {
        lines.append(text)
    }
}

private final class ScriptedPreconditionPromptInput: PromptInput, @unchecked Sendable {
    private var remaining: [String]
    init(scriptedLines: [String]) {
        self.remaining = scriptedLines
    }
    func readLine() -> String? {
        guard !remaining.isEmpty else { return nil }
        return remaining.removeFirst()
    }
}
