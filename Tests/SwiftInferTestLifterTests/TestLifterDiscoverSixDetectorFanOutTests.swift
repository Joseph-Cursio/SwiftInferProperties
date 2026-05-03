import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferTestLifter

/// TestLifter M5.5 acceptance — `TestLifter.discover(in:)` fans the
/// per-summary loop out to all six detectors (round-trip + idempotence
/// + commutativity from M1+M2 + monotonicity + countInvariance +
/// reduceEquivalence from M5.1+M5.2+M5.3) and surfaces a
/// `LiftedSuggestion` with the matching `DetectedPattern` enum case +
/// matching cross-validation key for each detection.
@Suite("TestLifter.discover — six-pattern fan-out (M5.5)")
struct TestLifterDiscoverSixDetectorFanOutTests {

    @Test("Discover surfaces all six pattern types from a six-test mixed suite")
    func sixTestSuiteFansOut() throws {
        let directory = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSixPatternTests(in: directory)

        let artifacts = try TestLifter.discover(in: directory)
        #expect(artifacts.liftedSuggestions.count == 6)

        let templateNames = artifacts.liftedSuggestions.map(\.templateName).sorted()
        // M5.0 cross-validation keys: monotonicity → "monotonicity",
        // countInvariance → "invariant-preservation",
        // reduceEquivalence → "associativity".
        #expect(templateNames == [
            "associativity",
            "commutativity",
            "idempotence",
            "invariant-preservation",
            "monotonicity",
            "round-trip"
        ])

        let monotonicity = try #require(
            artifacts.liftedSuggestions.first { $0.templateName == "monotonicity" }
        )
        if case .monotonicity(let detection) = monotonicity.pattern {
            #expect(detection.calleeName == "applyDiscount")
            #expect(detection.leftArgName == "a")
            #expect(detection.rightArgName == "b")
        } else {
            Issue.record("monotonicity suggestion missing .monotonicity pattern case")
        }

        let countInvariance = try #require(
            artifacts.liftedSuggestions.first { $0.templateName == "invariant-preservation" }
        )
        if case .countInvariance(let detection) = countInvariance.pattern {
            #expect(detection.calleeName == "filter")
            #expect(detection.inputBindingName == "xs")
        } else {
            Issue.record("invariant-preservation suggestion missing .countInvariance pattern case")
        }

        let reduceEquivalence = try #require(
            artifacts.liftedSuggestions.first { $0.templateName == "associativity" }
        )
        if case .reduceEquivalence(let detection) = reduceEquivalence.pattern {
            #expect(detection.opCalleeName == "+")
            #expect(detection.seedSource == "0")
            #expect(detection.collectionBindingName == "items")
        } else {
            Issue.record("associativity suggestion missing .reduceEquivalence pattern case")
        }

        // Cross-validation keys cover all six pattern + callee combinations.
        let keys = artifacts.crossValidationKeys
        #expect(keys.contains(CrossValidationKey(templateName: "monotonicity", calleeNames: ["applyDiscount"])))
        #expect(keys.contains(CrossValidationKey(templateName: "invariant-preservation", calleeNames: ["filter"])))
        #expect(keys.contains(CrossValidationKey(templateName: "associativity", calleeNames: ["+"])))
    }

    @Test("Origin is populated for the M5.5 detector outputs")
    func liftedOriginsArePopulated() throws {
        let directory = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSixPatternTests(in: directory)

        let artifacts = try TestLifter.discover(in: directory)
        let m5Templates: Set<String> = ["monotonicity", "invariant-preservation", "associativity"]
        let m5Suggestions = artifacts.liftedSuggestions.filter { m5Templates.contains($0.templateName) }
        #expect(m5Suggestions.count == 3)
        for suggestion in m5Suggestions {
            let origin = try #require(suggestion.origin)
            #expect(!origin.testMethodName.isEmpty)
        }
    }

    // MARK: - Fixture helpers

    private func makeFixtureDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestLifterSixFanOut-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writeSixPatternTests(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try writeFixture(SixPatternFixture.roundTrip, to: tests)
        try writeFixture(SixPatternFixture.idempotence, to: tests)
        try writeFixture(SixPatternFixture.commutativity, to: tests)
        try writeFixture(SixPatternFixture.monotonicity, to: tests)
        try writeFixture(SixPatternFixture.countInvariance, to: tests)
        try writeFixture(SixPatternFixture.reduceEquivalence, to: tests)
    }

    private func writeFixture(_ fixture: SixPatternFixture, to directory: URL) throws {
        try fixture.body.write(
            to: directory.appendingPathComponent(fixture.fileName),
            atomically: true,
            encoding: .utf8
        )
    }
}

/// One per-pattern test-source fixture for the six-detector fan-out
/// integration test. Holds the file name + body as a value so the
/// orchestrator stays under SwiftLint's function-body-length cap.
private struct SixPatternFixture {
    let fileName: String
    let body: String

    static let roundTrip = SixPatternFixture(
        fileName: "CodecTests.swift",
        body: """
        import XCTest

        final class CodecTests: XCTestCase {
            func testRoundTrip() {
                let original = MyData()
                let encoded = encode(original)
                let decoded = decode(encoded)
                XCTAssertEqual(original, decoded)
            }
        }
        """
    )

    static let idempotence = SixPatternFixture(
        fileName: "NormalizerTests.swift",
        body: """
        import XCTest

        final class NormalizerTests: XCTestCase {
            func testNormalizeIsIdempotent() {
                let s = "hello"
                let once = normalize(s)
                let twice = normalize(once)
                XCTAssertEqual(once, twice)
            }
        }
        """
    )

    static let commutativity = SixPatternFixture(
        fileName: "MergerTests.swift",
        body: """
        import XCTest

        final class MergerTests: XCTestCase {
            func testMergeIsCommutative() {
                let a = [1, 2]
                let b = [3, 4]
                XCTAssertEqual(merge(a, b), merge(b, a))
            }
        }
        """
    )

    static let monotonicity = SixPatternFixture(
        fileName: "PricingTests.swift",
        body: """
        import XCTest

        final class PricingTests: XCTestCase {
            func testApplyDiscountIsMonotonic() {
                let a = 5
                let b = 10
                XCTAssertLessThan(a, b)
                XCTAssertLessThanOrEqual(applyDiscount(a), applyDiscount(b))
            }
        }
        """
    )

    static let countInvariance = SixPatternFixture(
        fileName: "FilterTests.swift",
        body: """
        import XCTest

        final class FilterTests: XCTestCase {
            func testFilterPreservesCount() {
                let xs = [1, 2, 3, 4]
                XCTAssertEqual(filter(xs).count, xs.count)
            }
        }
        """
    )

    static let reduceEquivalence = SixPatternFixture(
        fileName: "ReducerTests.swift",
        body: """
        import XCTest

        final class ReducerTests: XCTestCase {
            func testSumReduceIsReversalInvariant() {
                let items = [1, 2, 3]
                XCTAssertEqual(items.reduce(0, +), items.reversed().reduce(0, +))
            }
        }
        """
    )
}
