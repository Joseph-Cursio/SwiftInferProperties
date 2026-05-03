import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M1.5 acceptance — the canonical end-to-end "discover walks
/// both Sources/ and Tests/, TestLifter contributes a CrossValidationKey
/// for the encode/decode body, RoundTripTemplate's suggestion for the
/// same pair picks up the +20 PRD §4.1 cross-validation signal" path.
@Suite("TestLifter — cross-validation lights up +20 end-to-end (M1.5)")
struct TestLifterCrossValidationTests {

    @Test("Discover with Sources/ encode-decode + Tests/ round-trip body lights up +20")
    func endToEndCrossValidation() throws {
        let directory = try makeFixtureDirectory(name: "TestLifterCrossValidation")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSourcesEncodeDecode(in: directory)
        try writeTestsRoundTripBody(in: directory)

        let liftedArtifacts = try TestLifter.discover(in: directory)
        #expect(liftedArtifacts.liftedSuggestions.count == 1)
        let liftedKeys = liftedArtifacts.crossValidationKeys

        let baseline = try TemplateRegistry.discover(in: directory)
        let baselineRoundTrip = try #require(baseline.first { $0.templateName == "round-trip" })
        let baselineTotal = baselineRoundTrip.score.total

        let crossValidated = try TemplateRegistry.discover(
            in: directory,
            crossValidationFromTestLifter: liftedKeys
        )
        let lifted = try #require(crossValidated.first { $0.templateName == "round-trip" })
        #expect(lifted.score.total == baselineTotal + 20)
        #expect(lifted.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
        #expect(
            lifted.explainability.whySuggested.contains { $0.contains("Cross-validated by TestLifter") }
        )
    }

    @Test("Discover pipeline (CLI surface) wires TestLifter automatically")
    func cliPipelineWiresTestLifter() throws {
        let directory = try makeFixtureDirectory(name: "TestLifterPipeline")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSourcesEncodeDecode(in: directory)
        try writeTestsRoundTripBody(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentDiagnostics()
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "round-trip" })
        // The CLI wired-in TestLifter should have surfaced the test
        // body's round-trip and contributed its key, so the +20 signal
        // is on the discover output without the test having to thread
        // anything manually.
        #expect(lifted.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
    }

    @Test("Test-side body without a matching Sources/ pair contributes no spurious +20")
    func testWithoutMatchingSourcePair() throws {
        let directory = try makeFixtureDirectory(name: "TestLifterUnmatched")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSourcesEncodeDecode(in: directory)
        // Test body uses serialize/deserialize — different callee names
        // than encode/decode, so the keys don't collide.
        try """
        import XCTest
        @testable import Foo

        final class CodecTests: XCTestCase {
            func testRoundTrip() {
                let original = MyData()
                let serialized = serialize(original)
                let deserialized = deserialize(serialized)
                XCTAssertEqual(original, deserialized)
            }
        }
        """.write(
            to: directory.appendingPathComponent("CodecTests.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentDiagnostics()
        )
        let lifted = try #require(result.suggestions.first { $0.templateName == "round-trip" })
        // The test's serialize/deserialize key DOESN'T match Sources's
        // encode/decode pair. The +20 should NOT fire.
        #expect(!lifted.score.signals.contains { $0.kind == .crossValidation })
    }

    // MARK: - Fixture helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestLifterIT-\(name)-\(UUID().uuidString)")
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
}

/// No-op diagnostic sink — the cross-validation tests don't care about
/// the warning stream from ConfigLoader / VocabularyLoader because the
/// fixture directories don't carry config files.
private struct SilentDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_ message: String) {}
}
