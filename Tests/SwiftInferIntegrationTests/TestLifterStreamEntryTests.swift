import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M3.2 acceptance — lifted suggestions whose callee has no
/// matching production-side function enter the visible `discover`
/// stream as promoted Suggestions with a +50 `.testBodyPattern` signal,
/// recovered (or `?`-sentinel) evidence, and the inferred generator
/// (or `.todo`). Lifted suggestions whose key matches a TemplateEngine-
/// side suggestion are suppressed — the +20 cross-validation signal
/// already communicates the corroboration.
@Suite("TestLifter — stream-entry + suppression (M3.2)")
struct TestLifterStreamEntryTests {

    // MARK: - Stream entry: lifted suggestions surface when no production-side match exists

    @Test("Round-trip lifted with no production-side match enters the stream with +50 testBodyPattern signal")
    func roundTripStreamEntryWithoutProductionMatch() throws {
        let directory = try makeFixtureDirectory(name: "RoundTripStreamEntry")
        defer { try? FileManager.default.removeItem(at: directory) }
        // Test references serialize/deserialize callees that are not
        // defined anywhere in the corpus. FunctionScanner sees no
        // matching summaries, so RoundTripTemplate doesn't fire on the
        // production side. After M3.2 the lifted suggestion still
        // surfaces as a promoted Suggestion in the stream.
        try writeUnmatchedRoundTripTest(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentDiagnostics()
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "round-trip" })
        // Promoted lifted Suggestion carries +50 `.testBodyPattern` per PRD §4.1.
        #expect(lifted.score.signals.contains { $0.kind == .testBodyPattern && $0.weight == 50 })
        // Origin is populated from the originating test method.
        let origin = try #require(lifted.liftedOrigin)
        #expect(origin.testMethodName == "testRoundTrip")
        // No FunctionSummary match → `?` sentinel evidence; generator
        // stays `.notYetComputed` (M3.3 accept-flow will render `.todo`).
        #expect(lifted.evidence.allSatisfy { $0.signature == "(?) -> ?" })
        #expect(lifted.generator.source == .notYetComputed)
    }

    @Test("Idempotence lifted with no production-side match enters the stream")
    func idempotenceStreamEntryWithoutProductionMatch() throws {
        let directory = try makeFixtureDirectory(name: "IdempotenceStreamEntry")
        defer { try? FileManager.default.removeItem(at: directory) }
        // Test references a callee `rebalance` that is not defined
        // anywhere in the corpus AND is not in the IdempotenceTemplate
        // curated list. FunctionScanner has no summary for it →
        // TemplateEngine doesn't fire → suppression doesn't kick in.
        // Type recovery falls back to `(?) -> ?` sentinel.
        try writeUnmatchedIdempotenceTest(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentDiagnostics()
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "idempotence" })
        #expect(lifted.score.signals.contains { $0.kind == .testBodyPattern && $0.weight == 50 })
        #expect(lifted.evidence[0].signature == "(?) -> ?")
        let origin = try #require(lifted.liftedOrigin)
        #expect(origin.testMethodName == "testRebalanceIsIdempotent")
    }

    @Test("Commutativity lifted with no production-side match enters the stream")
    func commutativityStreamEntryWithoutProductionMatch() throws {
        let directory = try makeFixtureDirectory(name: "CommutativityStreamEntry")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeUnmatchedCommutativityTest(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentDiagnostics()
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "commutativity" })
        #expect(lifted.score.signals.contains { $0.kind == .testBodyPattern && $0.weight == 50 })
        let origin = try #require(lifted.liftedOrigin)
        #expect(origin.testMethodName == "testCombineIsCommutative")
    }

    // MARK: - Suppression: lifted suggestion dropped when TemplateEngine has matching key

    @Test("Round-trip lifted with production-side match is suppressed; only TemplateEngine entry appears with +20")
    func suppressionOnProductionMatch() throws {
        let directory = try makeFixtureDirectory(name: "RoundTripSuppression")
        defer { try? FileManager.default.removeItem(at: directory) }
        // Sources has encode/decode + Tests has the matching round-trip
        // body. RoundTripTemplate fires on the production side; lifted
        // suggestion's crossValidationKey matches → suppressed.
        try writeSourcesEncodeDecode(in: directory)
        try writeTestsRoundTripBody(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentDiagnostics()
        )
        let roundTripEntries = result.suggestions.filter { $0.templateName == "round-trip" }
        #expect(roundTripEntries.count == 1)
        let entry = try #require(roundTripEntries.first)
        // The surviving entry is the TemplateEngine one (no liftedOrigin).
        #expect(entry.liftedOrigin == nil)
        // Carries the existing +20 cross-validation signal from M1.5 wiring.
        #expect(entry.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
    }

    // MARK: - Fixture helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestLifterStreamEntry-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writeSourcesEncodeDecode(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources").appendingPathComponent("Foo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public struct MyData: Equatable {
            public init() {}
        }
        public func encode(_ value: MyData) -> Data {
            return Data()
        }
        public func decode(_ data: Data) -> MyData {
            return MyData()
        }
        """.write(
            to: sources.appendingPathComponent("Codec.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeTestsRoundTripBody(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest
        @testable import Foo

        final class CodecTests: XCTestCase {
            func testRoundTrip() {
                let original = MyData()
                let encoded = encode(original)
                let decoded = decode(encoded)
                XCTAssertEqual(original, decoded)
            }
        }
        """.write(
            to: tests.appendingPathComponent("CodecTests.swift"),
            atomically: true,
            encoding: .utf8
        )
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

    private func writeUnmatchedIdempotenceTest(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest

        final class FooTests: XCTestCase {
            func testRebalanceIsIdempotent() {
                let s = "hello"
                XCTAssertEqual(rebalance(rebalance(s)), rebalance(s))
            }
        }
        """.write(
            to: tests.appendingPathComponent("FooTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeUnmatchedCommutativityTest(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest

        final class FooTests: XCTestCase {
            func testCombineIsCommutative() {
                let a = 1
                let b = 2
                XCTAssertEqual(combine(a, b), combine(b, a))
            }
        }
        """.write(
            to: tests.appendingPathComponent("FooTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }
}

/// No-op diagnostic sink — the stream-entry tests don't care about the
/// warning stream from ConfigLoader / VocabularyLoader because the
/// fixture directories don't carry config files.
private struct SilentDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_ message: String) {}
}
