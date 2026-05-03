import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferTestLifter

/// TestLifter M2.3 acceptance — `TestLifter.discover(in:)` fans the
/// per-summary loop out to all three M1+M2 detectors (round-trip,
/// idempotence, commutativity) and surfaces a `LiftedSuggestion` with
/// the matching `DetectedPattern` enum case + matching cross-validation
/// key for each detection.
@Suite("TestLifter.discover — three-pattern fan-out (M2.3)")
struct TestLifterDiscoverFanOutTests {

    @Test("Discover surfaces round-trip + idempotence + commutativity from a mixed test suite")
    func mixedTestSuiteFansOut() throws {
        let directory = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeMixedTests(in: directory)

        let artifacts = try TestLifter.discover(in: directory)
        #expect(artifacts.liftedSuggestions.count == 3)

        let templateNames = artifacts.liftedSuggestions.map(\.templateName).sorted()
        #expect(templateNames == ["commutativity", "idempotence", "round-trip"])

        let roundTrip = try #require(
            artifacts.liftedSuggestions.first { $0.templateName == "round-trip" }
        )
        if case .roundTrip(let detection) = roundTrip.pattern {
            #expect(detection.forwardCallee == "encode")
            #expect(detection.backwardCallee == "decode")
        } else {
            Issue.record("round-trip suggestion missing .roundTrip pattern case")
        }

        let idempotence = try #require(
            artifacts.liftedSuggestions.first { $0.templateName == "idempotence" }
        )
        if case .idempotence(let detection) = idempotence.pattern {
            #expect(detection.calleeName == "normalize")
        } else {
            Issue.record("idempotence suggestion missing .idempotence pattern case")
        }

        let commutativity = try #require(
            artifacts.liftedSuggestions.first { $0.templateName == "commutativity" }
        )
        if case .commutativity(let detection) = commutativity.pattern {
            #expect(detection.calleeName == "merge")
        } else {
            Issue.record("commutativity suggestion missing .commutativity pattern case")
        }

        // Cross-validation keys must be the three expected single-/two-
        // callee combinations, byte-distinct because template names
        // namespace the keys.
        let keys = artifacts.crossValidationKeys
        #expect(keys.contains(CrossValidationKey(templateName: "round-trip", calleeNames: ["encode", "decode"])))
        #expect(keys.contains(CrossValidationKey(templateName: "idempotence", calleeNames: ["normalize"])))
        #expect(keys.contains(CrossValidationKey(templateName: "commutativity", calleeNames: ["merge"])))
    }

    @Test("Empty test directory produces empty Artifacts")
    func emptyDirectoryProducesEmptyArtifacts() throws {
        let directory = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifacts = try TestLifter.discover(in: directory)
        #expect(artifacts.liftedSuggestions.isEmpty)
        #expect(artifacts.crossValidationKeys.isEmpty)
    }

    @Test("Test method with no recognized assertion contributes nothing")
    func unrecognizedShapeContributesNothing() throws {
        let directory = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest

        final class UnrecognizedTests: XCTestCase {
            func testJustALiteral() {
                let x = 42
                XCTAssertEqual(x, 42)
            }
        }
        """.write(
            to: tests.appendingPathComponent("UnrecognizedTests.swift"),
            atomically: true,
            encoding: .utf8
        )

        let artifacts = try TestLifter.discover(in: directory)
        #expect(artifacts.liftedSuggestions.isEmpty)
    }

    // MARK: - Fixture helpers

    private func makeFixtureDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestLifterFanOut-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writeMixedTests(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)

        try """
        import XCTest

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

        try """
        import XCTest

        final class NormalizerTests: XCTestCase {
            func testNormalizeIsIdempotent() {
                let s = "hello"
                let once = normalize(s)
                let twice = normalize(once)
                XCTAssertEqual(once, twice)
            }
        }
        """.write(
            to: tests.appendingPathComponent("NormalizerTests.swift"),
            atomically: true,
            encoding: .utf8
        )

        try """
        import XCTest

        final class MergerTests: XCTestCase {
            func testMergeIsCommutative() {
                let a = [1, 2]
                let b = [3, 4]
                XCTAssertEqual(merge(a, b), merge(b, a))
            }
        }
        """.write(
            to: tests.appendingPathComponent("MergerTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }
}
