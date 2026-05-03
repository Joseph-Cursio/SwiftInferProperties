import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M5.6 acceptance bar item (g) — `MonotonicityTemplate`
/// Possible→Likely escalation works end-to-end. A function whose
/// pre-cross-validation score lands in `.possible` (codomain-only:
/// `(Int) -> Int` shape with no curated-verb name match, no
/// `@CheckProperty(.monotonic(...))` annotation) lands in `.likely`
/// after M5.5's discover wiring threads the +20 signal through.
@Suite("MonotonicityTemplate — Possible→Likely escalation via TestLifter +20 (M5.6)")
struct MonotonicityEscalationTests {

    @Test("Codomain-only monotonicity Suggestion in .possible escalates to .likely with TestLifter cross-validation")
    func codomainOnlyMonotonicityEscalates() throws {
        let directory = try makeFixtureDirectory(name: "MonotonicityEscalation")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSourcesNonCuratedMonotonic(in: directory)
        try writeTestsMonotonicBody(in: directory)

        // Baseline: no TestLifter input → only codomain signal fires →
        // .possible tier.
        let baseline = try TemplateRegistry.discover(in: directory)
        let baselineMonotonic = try #require(baseline.first { $0.templateName == "monotonicity" })
        #expect(
            baselineMonotonic.score.tier == .possible,
            """
            Baseline monotonicity tier should be .possible for a function whose name doesn't \
            match curated verbs (was \(baselineMonotonic.score.tier))
            """
        )

        // With TestLifter cross-validation: the +20 signal pushes the
        // score above the .likely threshold.
        let liftedArtifacts = try TestLifter.discover(in: directory)
        let liftedKeys = liftedArtifacts.crossValidationKeys
        let crossValidated = try TemplateRegistry.discover(
            in: directory,
            crossValidationFromTestLifter: liftedKeys
        )
        let escalated = try #require(crossValidated.first { $0.templateName == "monotonicity" })
        #expect(
            escalated.score.tier == .likely,
            """
            Post-cross-validation monotonicity tier should be .likely \
            (was \(escalated.score.tier), score: \(escalated.score.total))
            """
        )
        #expect(escalated.score.total == baselineMonotonic.score.total + 20)
        #expect(escalated.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
    }

    // MARK: - Fixture helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("MonotonicityEscalationIT-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// `quux` doesn't match `MonotonicityTemplate.curatedVerbs` (length,
    /// count, score, depth, height, level, age, distance, time, size,
    /// width, area, weight, etc.), so the production side fires only
    /// on the codomain Comparable signal — landing the suggestion at
    /// .possible tier baseline.
    private func writeSourcesNonCuratedMonotonic(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources").appendingPathComponent("Foo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public func quux(_ x: Int) -> Int {
            return x + 1
        }
        """.write(
            to: sources.appendingPathComponent("Quux.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeTestsMonotonicBody(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest
        @testable import Foo

        final class QuuxTests: XCTestCase {
            func testQuuxIsMonotonic() {
                let a = 5
                let b = 10
                XCTAssertLessThan(a, b)
                XCTAssertLessThanOrEqual(quux(a), quux(b))
            }
        }
        """.write(
            to: tests.appendingPathComponent("QuuxTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }
}
