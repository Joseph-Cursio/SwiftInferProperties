import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M13.3 — end-to-end integration tests for the M13 plan
/// acceptance bar:
/// 1. Three-class enum corpus surfaces an `NClassEquivalenceClassHint`
///    + accept writes the expected comment-only file under
///    `Tests/Generated/SwiftInfer/equivalence-class/`.
/// 2. Two-class XCTAssertFalse corpus surfaces an M11-shape hint with
///    `coversDomain: true` + accept writes the comment block including
///    the negation-property exhaustiveness line.
@Suite("TestLifter — accept-flow equivalence-class rendering integration (M13.3)")
struct EquivalenceClassRenderingNClassTests {

    // MARK: - M13.3a: coversDomain comment surfaces

    @Test("XCTAssertTrue/XCTAssertFalse corpus → hint.coversDomain true → exhaustiveness comment in writeout")
    func acceptCanonicalCorpusEmitsExhaustivenessComment() throws {
        let directory = try makeFixtureDirectory(name: "AcceptCoversDomain")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeValidInvalidCanonicalFixture(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentNCDiagnostics()
        )
        let advisory = try #require(result.suggestions.first { $0.templateName == "equivalence-class" })
        let kind = try #require(result.equivalenceClassHintsByIdentity[advisory.identity])
        guard case .twoClass(let hint) = kind else {
            Issue.record("expected two-class hint kind"); return
        }
        #expect(hint.coversDomain == true)

        let recorded = RecordingNCOutput()
        let scripted = ScriptedNCPromptInput(scriptedLines: ["A"])
        let context = InteractiveTriage.Context(
            prompt: scripted,
            output: recorded,
            diagnostics: SilentNCDiagnosticOutput(),
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
        #expect(contents.contains("Exhaustiveness: forAll x: String."))
        #expect(contents.contains("isValid(x) ∨ ¬isValid(x)"))
    }

    @Test("XCTAssertTrue + XCTAssertTrue(!pred) corpus → coversDomain false → no exhaustiveness comment")
    func acceptNegatedNegativeBucketDropsCoversDomain() throws {
        let directory = try makeFixtureDirectory(name: "AcceptCoversDomainNegated")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeNegatedNegativeBucketFixture(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentNCDiagnostics()
        )
        let advisory = try #require(result.suggestions.first { $0.templateName == "equivalence-class" })
        let kind = try #require(result.equivalenceClassHintsByIdentity[advisory.identity])
        guard case .twoClass(let hint) = kind else {
            Issue.record("expected two-class hint kind"); return
        }
        #expect(hint.coversDomain == false)

        let recorded = RecordingNCOutput()
        let scripted = ScriptedNCPromptInput(scriptedLines: ["A"])
        let context = InteractiveTriage.Context(
            prompt: scripted,
            output: recorded,
            diagnostics: SilentNCDiagnosticOutput(),
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
        #expect(!contents.contains("Exhaustiveness:"))
    }

    // MARK: - M13.3b/c: N-class corpus end-to-end

    @Test("Three-class enum corpus surfaces NClassEquivalenceClassHint + accept writes file with markerSet suffix")
    func acceptNClassThreeBucketCorpus() throws {
        let directory = try makeFixtureDirectory(name: "AcceptNClassThreeBucket")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeNClassFixture(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentNCDiagnostics()
        )
        let advisory = try #require(result.suggestions.first { $0.templateName == "equivalence-class" })
        #expect(advisory.score.tier == .advisory)
        let kind = try #require(result.equivalenceClassHintsByIdentity[advisory.identity])
        guard case .nClass(let hint) = kind else {
            Issue.record("expected N-class hint kind, got \(kind)"); return
        }
        #expect(hint.predicateName == "size")
        #expect(hint.markerSetName == "Sizes")
        #expect(hint.markers.count == 3)
        #expect(hint.siteCountsByMarker["Small"] == 3)
        #expect(hint.siteCountsByMarker["Medium"] == 3)
        #expect(hint.siteCountsByMarker["Large"] == 3)

        let recorded = RecordingNCOutput()
        let scripted = ScriptedNCPromptInput(scriptedLines: ["A"])
        let context = InteractiveTriage.Context(
            prompt: scripted,
            output: recorded,
            diagnostics: SilentNCDiagnosticOutput(),
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
        // M13 plan OD #6 — accept-flow filename: <predicate>_<markerSetName>
        #expect(writtenPath.lastPathComponent == "EquivalenceClasses_size_sizes.swift")
        let parentDir = writtenPath.deletingLastPathComponent().lastPathComponent
        #expect(parentDir == "equivalence-class")
        let contents = try String(contentsOf: writtenPath, encoding: .utf8)
        #expect(contents.contains("Inferred N-class equivalence partition for size"))
        #expect(contents.contains("3 test methods named Small*"))
        #expect(contents.contains("3 test methods named Medium*"))
        #expect(contents.contains("3 test methods named Large*"))
        #expect(contents.contains("filter { size($0) == .small }"))
        #expect(contents.contains("filter { size($0) == .medium }"))
        #expect(contents.contains("filter { size($0) == .large }"))
        // M14.2 — same-target enum case enumeration is now wired through
        // the discover pipeline; the markerSet covers every case of
        // Size, so the renderer surfaces the exhaustiveness comment.
        #expect(hint.coversDomain == true)
        #expect(contents.contains("Exhaustiveness: forAll x: Box."))
        #expect(contents.contains("p(x) == .small ∨ p(x) == .medium ∨ p(x) == .large"))
    }

    // The "partial enum coverage → coversDomain false" companion test
    // lives in `EquivalenceClassRenderingNClassCoversDomainTests` —
    // moved out at M14.2 to keep this struct under SwiftLint's
    // `type_body_length` cap. The fixture-builder helpers stay here
    // since both files share the same `writeSizerVocabulary` /
    // `writeSizerTests` shape.

    // MARK: - Fixtures

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("EquivalenceClassRenderingNClass-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writeValidInvalidCanonicalFixture(in directory: URL) throws {
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
            atomically: true, encoding: .utf8
        )
    }

    private func writeNegatedNegativeBucketFixture(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources").appendingPathComponent("Foo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public func isValid(_ s: String) -> Bool {
            return s.contains("@")
        }
        """.write(to: sources.appendingPathComponent("Validator.swift"), atomically: true, encoding: .utf8)

        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        // Negative bucket uses XCTAssertTrue(!pred(x)) instead of
        // XCTAssertFalse(pred(x)) — non-canonical, drops coversDomain.
        try """
        import XCTest

        final class ValidatorTests: XCTestCase {
            func testValid_simple() { XCTAssertTrue(isValid("a@b.c")) }
            func testValid_withPlus() { XCTAssertTrue(isValid("a+1@b.c")) }
            func testValid_subdomain() { XCTAssertTrue(isValid("a@b.c.d")) }
            func testInvalid_noAt() { XCTAssertTrue(!isValid("abc")) }
            func testInvalid_empty() { XCTAssertTrue(!isValid("")) }
            func testInvalid_atOnly() { XCTAssertTrue(!isValid("@")) }
        }
        """.write(
            to: tests.appendingPathComponent("ValidatorTests.swift"),
            atomically: true, encoding: .utf8
        )
    }

    private func writeNClassFixture(in directory: URL) throws {
        try writeSizerSource(in: directory)
        try writeSizerVocabulary(in: directory)
        try writeSizerTests(in: directory)
    }

    private func writeSizerSource(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources").appendingPathComponent("Foo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public enum Size: Equatable {
            case small, medium, large
        }

        public func size(_ box: Box) -> Size {
            switch box.count {
            case 0..<10: return .small
            case 10..<100: return .medium
            default: return .large
            }
        }

        public struct Box: Equatable {
            public let count: Int
            public init(count: Int) { self.count = count }
        }
        """.write(to: sources.appendingPathComponent("Sizer.swift"), atomically: true, encoding: .utf8)
    }

    private func writeSizerVocabulary(in directory: URL) throws {
        // Marker set is supplied via .swiftinfer/vocabulary.json so the
        // discover-loop's effective marker table picks it up via M13.3
        // vocabulary plumbing.
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
        // Package.swift anchors the implicit walk-up.
        try "// swift-tools-version: 6.1\n".write(
            to: directory.appendingPathComponent("Package.swift"),
            atomically: true, encoding: .utf8
        )
    }

    private func writeSizerTests(in directory: URL) throws {
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

private struct SilentNCDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_: String) { /* no-op */ }
}

private final class SilentNCDiagnosticOutput: DiagnosticOutput, @unchecked Sendable {
    func writeDiagnostic(_: String) { /* no-op */ }
}

private final class RecordingNCOutput: DiscoverOutput, @unchecked Sendable {
    private(set) var lines: [String] = []
    var text: String { lines.joined(separator: "\n") }

    func write(_ text: String) {
        lines.append(text)
    }
}

private final class ScriptedNCPromptInput: PromptInput, @unchecked Sendable {
    private var remaining: [String]

    init(scriptedLines: [String]) {
        self.remaining = scriptedLines
    }
    func readLine() -> String? {
        guard !remaining.isEmpty else { return nil }
        return remaining.removeFirst()
    }
}
