import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// PRD v0.4 §13 numerical acceptance for TestLifter M4.3 — verbatim:
///
/// > Mock-based generator synthesis produces a valid `Gen<T>` for at
/// > least 50% of the types where ≥3 test sites construct via the same
/// > initializer.
///
/// Builds a synthetic test corpus where 6 distinct types are
/// constructed via the same initializer at ≥3 sites each (clearing
/// the M4.3 threshold) and 4 distinct types are constructed at <3
/// sites (under threshold). Asserts ≥50% of the ≥3-site cohort gets a
/// non-`.todo` `Gen<T>` after the discover pipeline runs. With the M4
/// implementation that's actually 100% (every clear-threshold type
/// gets a mock generator); the 50% bar is calibrated against the PRD
/// to leave room for future domain-specific exclusions without
/// breaking the acceptance criterion.
@Suite("TestLifter — PRD §13 mock-synthesis coverage (M4.5)")
struct MockSynthesisCoverageTests {

    @Test("≥50% of types with ≥3 same-shape construction sites get a non-.todo Gen<T>")
    func fiftyPercentCoverageBar() throws {
        let directory = try makeFixture(name: "Coverage")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeCoverageFixture(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentCovDiagnostics()
        )

        // Round-trip lifted suggestions, one per type — 10 types
        // total. The 6 above-threshold types should all show up with
        // mock-inferred generators; the 4 under-threshold types
        // should remain at `.notYetComputed` (rendered as `?.gen()` by
        // the M3.3 path).
        let liftedRoundTrips = result.suggestions.filter { $0.templateName == "round-trip" }
        let aboveThresholdHits = liftedRoundTrips.filter { suggestion in
            suggestion.generator.source == .inferredFromTests
                && suggestion.mockGenerator != nil
        }

        // The fixture builds 6 above-threshold types. Conservative
        // bar: at least 3 should hit (50% of 6). The implementation
        // achieves 6/6 → 100% against this fixture; if a future
        // change drops coverage below the 50% bar, the test catches
        // it before release.
        let aboveThresholdCount = 6
        let coverage = Double(aboveThresholdHits.count) / Double(aboveThresholdCount)
        #expect(
            coverage >= 0.5,
            """
            Mock-synthesis coverage \(aboveThresholdHits.count)/\(aboveThresholdCount) \
            (\(Int(coverage * 100))%) below the §13 50% bar
            """
        )
    }

    // MARK: - Fixture

    private func makeFixture(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("MockCoverage-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Build a test corpus with 6 above-threshold types (3+ sites
    /// each) and 4 under-threshold types (1-2 sites). Each type has
    /// one round-trip test method using test-only callees (so the
    /// M3.1 FunctionSummary lookup misses → M4.2 annotation tier
    /// recovers `T` → M4.3 mock fallback fires when ≥3 sites exist).
    private func writeCoverageFixture(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("CoverageTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        // Above-threshold types — three Foo*(...) construction sites each.
        for index in 0..<6 {
            let typeName = "TypeAbove\(index)"
            try """
            import XCTest
            final class TypeAbove\(index)Tests: XCTestCase {
                func testRoundTrip() {
                    let original: \(typeName) = \(typeName)(value: 1)
                    let serialized = serialize\(index)(original)
                    let deserialized = deserialize\(index)(serialized)
                    XCTAssertEqual(original, deserialized)
                }

                func testFixtureA() {
                    let a = \(typeName)(value: 2)
                    XCTAssertNotNil(a)
                }

                func testFixtureB() {
                    let b = \(typeName)(value: 3)
                    XCTAssertNotNil(b)
                }
            }
            """.write(
                to: tests.appendingPathComponent("\(typeName)Tests.swift"),
                atomically: true,
                encoding: .utf8
            )
        }
        // Under-threshold types — single construction site each.
        for index in 0..<4 {
            let typeName = "TypeBelow\(index)"
            try """
            import XCTest
            final class TypeBelow\(index)Tests: XCTestCase {
                func testRoundTrip() {
                    let original: \(typeName) = \(typeName)(value: 1)
                    let serialized = under\(index)Serialize(original)
                    let deserialized = under\(index)Deserialize(serialized)
                    XCTAssertEqual(original, deserialized)
                }
            }
            """.write(
                to: tests.appendingPathComponent("\(typeName)Tests.swift"),
                atomically: true,
                encoding: .utf8
            )
        }
    }
}

// MARK: - Test doubles

private struct SilentCovDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_ message: String) {}
}
