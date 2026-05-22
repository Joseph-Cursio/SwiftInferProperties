import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M11.2 — end-to-end integration test verifying that
/// (a) a Valid/Invalid test corpus surfaces a `.advisory`-tier
/// equivalence-class suggestion through `Discover.collectVisibleSuggestions`,
/// (b) the PipelineResult's `equivalenceClassHintsByIdentity` map
/// contains the hint, (c) accept-flow writes the comment-only
/// documentation block to `Tests/Generated/SwiftInfer/equivalence-class/EquivalenceClasses_<predicate>.swift`,
/// and (d) the throwing-predicate variant emits the comment with the
/// `.predicateThrows` veto reason in place of the suggested generators.
@Suite("TestLifter — accept-flow equivalence-class rendering integration (M11.2)")
struct EquivalenceClassRenderingTests {

    @Test("Valid/Invalid corpus surfaces .advisory equivalence-class suggestion + writes comment-only file on accept")
    func acceptEquivalenceClassWritesDocumentationBlock() throws {
        let directory = try makeFixtureDirectory(name: "AcceptEquivalenceClass")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeEquivalenceClassFixture(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentECDiagnostics()
        )
        let advisory = try #require(result.suggestions.first { $0.templateName == "equivalence-class" })
        #expect(advisory.score.tier == .advisory)
        #expect(advisory.identity.canonicalInput.contains("equivalence-class"))
        let kind = try #require(result.equivalenceClassHintsByIdentity[advisory.identity])
        guard case .twoClass(let hint) = kind else {
            Issue.record("expected two-class hint kind"); return
        }
        #expect(hint.predicateName == "isValid")
        #expect(hint.positiveSiteCount == 3)
        #expect(hint.negativeSiteCount == 3)
        #expect(hint.predicateVeto == nil)

        let recorded = RecordingECOutput()
        let scripted = ScriptedECPromptInput(scriptedLines: ["A"])
        let context = InteractiveTriage.Context(
            prompt: scripted,
            output: recorded,
            diagnostics: SilentECDiagnosticOutput(),
            outputDirectory: directory,
            dryRun: false,
            equivalenceClassHintsByIdentity: result.equivalenceClassHintsByIdentity
        )
        let outcome = try InteractiveTriage.run(
            suggestions: [advisory],
            existingDecisions: .empty,
            context: context
        )

        let writtenPath = try #require(outcome.writtenFiles.first)
        #expect(writtenPath.lastPathComponent == "EquivalenceClasses_isValid.swift")
        let parentDir = writtenPath.deletingLastPathComponent().lastPathComponent
        #expect(parentDir == "equivalence-class")
        let contents = try String(contentsOf: writtenPath, encoding: .utf8)
        #expect(contents.contains("Inferred predicate equivalence class for isValid"))
        #expect(contents.contains("3 test methods named Valid*"))
        #expect(contents.contains("3 test methods named Invalid*"))
        #expect(contents.contains("Suggested generator for Valid class"))
        #expect(contents.contains("Suggested generator for Invalid class"))
        #expect(contents.contains("filter(isValid)"))
        #expect(contents.contains("filter { !isValid"))
        #expect(!contents.contains("Generator narrowing skipped"))
    }

    @Test("Throwing predicate surfaces vetoed equivalence-class hint + writes comment-only file with veto reason")
    func acceptVetoedEquivalenceClassWritesVetoReason() throws {
        let directory = try makeFixtureDirectory(name: "AcceptEquivalenceClassVeto")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeThrowingPredicateFixture(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentECDiagnostics()
        )
        let advisory = try #require(result.suggestions.first { $0.templateName == "equivalence-class" })
        let kind = try #require(result.equivalenceClassHintsByIdentity[advisory.identity])
        guard case .twoClass(let hint) = kind else {
            Issue.record("expected two-class hint kind"); return
        }
        #expect(hint.predicateVeto == .predicateThrows)

        let recorded = RecordingECOutput()
        let scripted = ScriptedECPromptInput(scriptedLines: ["A"])
        let context = InteractiveTriage.Context(
            prompt: scripted,
            output: recorded,
            diagnostics: SilentECDiagnosticOutput(),
            outputDirectory: directory,
            dryRun: false,
            equivalenceClassHintsByIdentity: result.equivalenceClassHintsByIdentity
        )
        let outcome = try InteractiveTriage.run(
            suggestions: [advisory],
            existingDecisions: .empty,
            context: context
        )

        let writtenPath = try #require(outcome.writtenFiles.first)
        let contents = try String(contentsOf: writtenPath, encoding: .utf8)
        #expect(contents.contains("Generator narrowing skipped: predicate throws"))
        #expect(!contents.contains("Suggested generator for Valid class:"))
        #expect(!contents.contains("Suggested generator for Invalid class:"))
    }

    @Test("Validate substring does NOT trigger Valid marker (token-boundary regression)")
    func validateSubstringDoesNotTriggerMarker() throws {
        let directory = try makeFixtureDirectory(name: "ValidateNonMatch")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeValidateFixture(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentECDiagnostics()
        )
        let advisory = result.suggestions.first { $0.templateName == "equivalence-class" }
        #expect(advisory == nil, "testValidate_* methods must NOT trigger the Valid marker")
    }

    // MARK: - Fixtures

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("EquivalenceClassRendering-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writeEquivalenceClassFixture(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources").appendingPathComponent("Foo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public func isValid(_ s: String) -> Bool {
            return s.contains("@")
        }
        """.write(to: sources.appendingPathComponent("Validator.swift"), atomically: true, encoding: .utf8)

        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest

        final class ValidatorTests: XCTestCase {
            func testValid_simple() { XCTAssertTrue(isValid("a@b.c")) }
            func testValid_withPlus() { XCTAssertTrue(isValid("a+1@b.c")) }
            func testValid_subdomain() { XCTAssertTrue(isValid("a@b.c.d")) }
            func testInvalid_noAt() { XCTAssertFalse(isValid("abc")) }
            func testInvalid_empty() { XCTAssertFalse(isValid("")) }
            func testInvalid_atOnly() { XCTAssertFalse(isValid("@")) }
        }
        """.write(
            to: tests.appendingPathComponent("ValidatorTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeThrowingPredicateFixture(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources").appendingPathComponent("Foo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public enum ValidationError: Error { case invalid }

        public func isValid(_ s: String) throws -> Bool {
            if s.isEmpty { throw ValidationError.invalid }
            return s.contains("@")
        }
        """.write(to: sources.appendingPathComponent("Validator.swift"), atomically: true, encoding: .utf8)

        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest

        final class ValidatorTests: XCTestCase {
            func testValid_simple() throws { XCTAssertTrue(try isValid("a@b.c")) }
            func testValid_withPlus() throws { XCTAssertTrue(try isValid("a+1@b")) }
            func testValid_subdomain() throws { XCTAssertTrue(try isValid("a@b.c.d")) }
            func testInvalid_noAt() throws { XCTAssertFalse(try isValid("abc")) }
            func testInvalid_atOnly() throws { XCTAssertFalse(try isValid("@")) }
            func testInvalid_double() throws { XCTAssertFalse(try isValid("a@b@c")) }
        }
        """.write(
            to: tests.appendingPathComponent("ValidatorTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeValidateFixture(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources").appendingPathComponent("Foo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public func validate(_ s: String) -> Bool {
            return !s.isEmpty
        }
        """.write(to: sources.appendingPathComponent("Validator.swift"), atomically: true, encoding: .utf8)

        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest

        final class ValidatorTests: XCTestCase {
            func testValidate_simple() { XCTAssertTrue(validate("abc")) }
            func testValidate_withPlus() { XCTAssertTrue(validate("a+b")) }
            func testValidate_subdomain() { XCTAssertTrue(validate("a.b.c")) }
        }
        """.write(
            to: tests.appendingPathComponent("ValidatorTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }
}

// MARK: - Test doubles

private struct SilentECDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_: String) { /* no-op */ }
}

private final class SilentECDiagnosticOutput: DiagnosticOutput, @unchecked Sendable {
    func writeDiagnostic(_: String) { /* no-op */ }
}

private final class RecordingECOutput: DiscoverOutput, @unchecked Sendable {
    private(set) var lines: [String] = []
    var text: String { lines.joined(separator: "\n") }

    func write(_ text: String) {
        lines.append(text)
    }
}

private final class ScriptedECPromptInput: PromptInput, @unchecked Sendable {
    private var remaining: [String]

    init(scriptedLines: [String]) {
        self.remaining = scriptedLines
    }
    func readLine() -> String? {
        guard !remaining.isEmpty else { return nil }
        return remaining.removeFirst()
    }
}
