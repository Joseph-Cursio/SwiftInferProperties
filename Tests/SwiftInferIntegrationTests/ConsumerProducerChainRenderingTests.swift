import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M16.3 — end-to-end integration test verifying that
/// (a) a `validate(format(...))` corpus surfaces a `.advisory`-tier
/// `consumer-producer-chain` suggestion through `Discover.collectVisibleSuggestions`,
/// (b) the PipelineResult's `consumerProducerChainHintsByIdentity` map
/// contains the hint, (c) accept-flow writes the comment-only
/// documentation block to `Tests/Generated/SwiftInfer/consumer-producer/<consumer>_<producer>.swift`,
/// and (d) the throws-producer variant emits the comment with the
/// `.producerThrows` veto reason in place of the suggested generator.
@Suite("TestLifter — accept-flow consumer-producer chain rendering integration (M16.3)")
struct ConsumerProducerChainRenderingTests {

    @Test("validate(format(doc)) corpus surfaces .advisory chain + writes file on accept")
    func acceptConsumerProducerChainWritesDocumentationBlock() throws {
        let directory = try makeFixtureDirectory(name: "AcceptConsumerProducerChain")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeChainFixture(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentChainDiagnostics()
        )
        let advisory = try #require(
            result.suggestions.first { $0.templateName == "consumer-producer-chain" }
        )
        #expect(advisory.score.tier == .advisory)
        #expect(advisory.identity.canonicalInput.contains("consumer-producer-chain"))
        let hint = try #require(result.consumerProducerChainHintsByIdentity[advisory.identity])
        #expect(hint.origin == .consumerProducerChain)
        #expect(hint.producerName == "format")
        #expect(hint.reverseName == "validate")
        #expect(hint.domainTypeName == "String")
        #expect(hint.siteCount == 3)
        #expect(hint.producerVeto == nil)

        let recorded = RecordingChainOutput()
        let scripted = ScriptedChainPromptInput(scriptedLines: ["A"])
        let context = InteractiveTriage.Context(
            prompt: scripted,
            output: recorded,
            diagnostics: SilentChainDiagnosticOutput(),
            outputDirectory: directory,
            dryRun: false,
            consumerProducerChainHintsByIdentity: result.consumerProducerChainHintsByIdentity
        )
        let outcome = try InteractiveTriage.run(
            suggestions: [advisory],
            existingDecisions: .empty,
            context: context
        )

        let writtenPath = try #require(outcome.writtenFiles.first)
        #expect(writtenPath.lastPathComponent == "validate_format.swift")
        let parentDir = writtenPath.deletingLastPathComponent().lastPathComponent
        #expect(parentDir == "consumer-producer")
        let contents = try String(contentsOf: writtenPath, encoding: .utf8)
        #expect(contents.contains("Inferred consumer-producer chain: validate ← format"))
        #expect(contents.contains("validate's argument was always format's output across 3 test sites"))
        #expect(contents.contains("Suggested narrowed generator: Gen<String>.map(format)"))
        #expect(!contents.contains("Generator narrowing skipped"))
    }

    @Test("Throws producer surfaces vetoed consumer-producer chain + writes comment-only file with veto reason")
    func acceptVetoedConsumerProducerChainWritesVetoReason() throws {
        let directory = try makeFixtureDirectory(name: "AcceptConsumerProducerChainVeto")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeThrowingProducerFixture(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentChainDiagnostics()
        )
        let advisory = try #require(
            result.suggestions.first { $0.templateName == "consumer-producer-chain" }
        )
        let hint = try #require(result.consumerProducerChainHintsByIdentity[advisory.identity])
        #expect(hint.producerVeto == .producerThrows)

        let recorded = RecordingChainOutput()
        let scripted = ScriptedChainPromptInput(scriptedLines: ["A"])
        let context = InteractiveTriage.Context(
            prompt: scripted,
            output: recorded,
            diagnostics: SilentChainDiagnosticOutput(),
            outputDirectory: directory,
            dryRun: false,
            consumerProducerChainHintsByIdentity: result.consumerProducerChainHintsByIdentity
        )
        let outcome = try InteractiveTriage.run(
            suggestions: [advisory],
            existingDecisions: .empty,
            context: context
        )

        let writtenPath = try #require(outcome.writtenFiles.first)
        let contents = try String(contentsOf: writtenPath, encoding: .utf8)
        #expect(contents.contains("Generator narrowing skipped: producer throws"))
        #expect(!contents.contains("Suggested narrowed generator:"))
    }

    @Test("Round-trip-pair corpus does NOT surface consumer-producer-chain (anti-double-fire)")
    func roundTripPairAntiDoubleFireSuppressesChain() throws {
        let directory = try makeFixtureDirectory(name: "ChainAntiDoubleFire")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeRoundTripPairFixture(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentChainDiagnostics()
        )
        let chainAdvisory = result.suggestions.first { $0.templateName == "consumer-producer-chain" }
        #expect(chainAdvisory == nil, "M5 round-trip pair should suppress the M16 chain advisory")
    }

    // MARK: - Fixtures

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConsumerProducerChainRendering-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Source-side: free-function `format(_:Doc) -> String` and
    /// `validate(_:String) -> Bool`. Test-side: 3 test methods each
    /// calling `validate(format(...))` with no round-trip-style
    /// assertion (just `XCTAssertTrue` on validate's result), so M5
    /// doesn't fire and M16 has the chain to itself.
    private func writeChainFixture(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources").appendingPathComponent("Docs")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public struct Doc {
            public let title: String
            public init(title: String) { self.title = title }
        }

        public func format(_ doc: Doc) -> String {
            return "<doc title=\\"\\(doc.title)\\">"
        }

        public func validate(_ s: String) -> Bool {
            return s.hasPrefix("<doc")
        }
        """.write(to: sources.appendingPathComponent("Doc.swift"), atomically: true, encoding: .utf8)

        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("DocsTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest

        final class ValidateFormatTests: XCTestCase {
            func testFormattedSimple() {
                let doc = Doc(title: "Hello")
                XCTAssertTrue(validate(format(doc)))
            }
            func testFormattedSpaces() {
                let doc = Doc(title: "Hello world")
                XCTAssertTrue(validate(format(doc)))
            }
            func testFormattedEmpty() {
                let doc = Doc(title: "")
                XCTAssertTrue(validate(format(doc)))
            }
        }
        """.write(
            to: tests.appendingPathComponent("ValidateFormatTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// Same chain shape but with a throws producer to exercise the
    /// veto path. The corpus uses `try!` at the call sites because
    /// `XCTAssertTrue` doesn't propagate; the M16 detector reads the
    /// producer's `FunctionSummary.isThrows` flag, so the test-side
    /// `try!` doesn't matter for veto computation.
    private func writeThrowingProducerFixture(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources").appendingPathComponent("Docs")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public enum FormatError: Error { case empty }

        public struct Doc {
            public let title: String
            public init(title: String) { self.title = title }
        }

        public func format(_ doc: Doc) throws -> String {
            if doc.title.isEmpty { throw FormatError.empty }
            return "<doc title=\\"\\(doc.title)\\">"
        }

        public func validate(_ s: String) -> Bool {
            return s.hasPrefix("<doc")
        }
        """.write(to: sources.appendingPathComponent("Doc.swift"), atomically: true, encoding: .utf8)

        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("DocsTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest

        final class ValidateFormatTests: XCTestCase {
            func testFormattedSimple() throws {
                let doc = Doc(title: "Hello")
                XCTAssertTrue(validate(try format(doc)))
            }
            func testFormattedSpaces() throws {
                let doc = Doc(title: "Hello world")
                XCTAssertTrue(validate(try format(doc)))
            }
            func testFormattedRich() throws {
                let doc = Doc(title: "Rich title")
                XCTAssertTrue(validate(try format(doc)))
            }
        }
        """.write(
            to: tests.appendingPathComponent("ValidateFormatTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// Round-trip-pair fixture: `decode(encode(t)) == t`. The
    /// `AssertAfterTransformDetector` should pick this up as an M5
    /// pair, suppressing the M16 chain detector via anti-double-fire.
    private func writeRoundTripPairFixture(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources").appendingPathComponent("Codec")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public struct Doc: Equatable {
            public let title: String
            public init(title: String) { self.title = title }
        }

        public func encode(_ doc: Doc) -> String {
            return doc.title
        }

        public func decode(_ s: String) -> Doc {
            return Doc(title: s)
        }
        """.write(to: sources.appendingPathComponent("Codec.swift"), atomically: true, encoding: .utf8)

        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("CodecTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest

        final class CodecRoundTripTests: XCTestCase {
            func testRoundTripSimple() {
                let doc = Doc(title: "Hello")
                XCTAssertEqual(decode(encode(doc)), doc)
            }
            func testRoundTripSpaces() {
                let doc = Doc(title: "Hello world")
                XCTAssertEqual(decode(encode(doc)), doc)
            }
            func testRoundTripEmpty() {
                let doc = Doc(title: "")
                XCTAssertEqual(decode(encode(doc)), doc)
            }
        }
        """.write(
            to: tests.appendingPathComponent("CodecRoundTripTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }
}

// MARK: - Test doubles

private struct SilentChainDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_ message: String) {}
}

private final class SilentChainDiagnosticOutput: DiagnosticOutput, @unchecked Sendable {
    func writeDiagnostic(_ text: String) {}
}

private final class RecordingChainOutput: DiscoverOutput, @unchecked Sendable {
    private(set) var lines: [String] = []
    var text: String { lines.joined(separator: "\n") }

    func write(_ text: String) {
        lines.append(text)
    }
}

private final class ScriptedChainPromptInput: PromptInput, @unchecked Sendable {
    private var remaining: [String]

    init(scriptedLines: [String]) {
        self.remaining = scriptedLines
    }
    func readLine() -> String? {
        guard !remaining.isEmpty else { return nil }
        return remaining.removeFirst()
    }
}
