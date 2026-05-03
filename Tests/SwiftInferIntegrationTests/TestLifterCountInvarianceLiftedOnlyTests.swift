import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M5.6 acceptance bar item (h) — count-invariance
/// **lifted-only** emission. When TestLifter detects
/// `f(xs).count == xs.count` in a test body BUT the production-side
/// `f` lacks the `@CheckProperty(.preservesInvariant(\.count))`
/// annotation, the production-side `InvariantPreservationTemplate`
/// doesn't fire (it's annotation-only per PRD §5.2 caveat). The
/// lifted-side LiftedSuggestion has no production-side counterpart to
/// suppress against, so it ENTERS the visible discover stream as a
/// freestanding count-invariant claim per M5 plan OD #1 default.
@Suite("TestLifter — count-invariance lifted-only emission (M5.6)")
struct TestLifterCountInvarianceLiftedOnlyTests {

    @Test("Unannotated filter source + count-invariant test body surfaces lifted-only suggestion")
    func liftedOnlyEntersVisibleStream() throws {
        let directory = try makeFixtureDirectory(name: "CountInvarianceLiftedOnly")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSourcesUnannotatedFilter(in: directory)
        try writeTestsCountInvariantBody(in: directory)

        // Production-side: no @CheckProperty annotation → no
        // InvariantPreservationTemplate suggestion in the baseline.
        let baseline = try TemplateRegistry.discover(in: directory)
        #expect(
            baseline.first { $0.templateName == "invariant-preservation" } == nil,
            "Baseline should NOT carry an InvariantPreservationTemplate suggestion (annotation-only template)"
        )

        // Discover pipeline: lifted-only suggestion enters the visible
        // stream because no production-side suggestion suppresses it.
        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: true,
            diagnostics: SilentLiftedOnlyDiagnostics()
        )
        let liftedOnly = try #require(
            result.suggestions.first { $0.templateName == "invariant-preservation" }
        )
        // The promoted suggestion carries a lifted origin (M3.0
        // promotion adapter sets `liftedOrigin` from the originating
        // test method) and the +50 testBodyPattern signal that lifted
        // suggestions ship with per the M3.0 score shape.
        #expect(liftedOnly.liftedOrigin != nil)
        #expect(liftedOnly.score.signals.contains { $0.kind == .testBodyPattern && $0.weight == 50 })
        // No +20 cross-validation signal — the lifted suggestion enters
        // alone (suppression is a no-op when there's no TemplateEngine
        // counterpart to merge against).
        #expect(!liftedOnly.score.signals.contains { $0.kind == .crossValidation })
    }

    // MARK: - Fixture helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("CountInvarianceLiftedOnlyIT-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// `filter(_:)` without the `@CheckProperty(.preservesInvariant(\.count))`
    /// annotation — InvariantPreservationTemplate stays silent.
    private func writeSourcesUnannotatedFilter(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources").appendingPathComponent("Foo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public func filter(_ xs: [Int]) -> [Int] {
            return xs
        }
        """.write(
            to: sources.appendingPathComponent("Filter.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeTestsCountInvariantBody(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests").appendingPathComponent("FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest
        @testable import Foo

        final class FilterTests: XCTestCase {
            func testFilterPreservesCount() {
                let xs = [1, 2, 3, 4]
                XCTAssertEqual(filter(xs).count, xs.count)
            }
        }
        """.write(
            to: tests.appendingPathComponent("FilterTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }
}

private struct SilentLiftedOnlyDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_ message: String) {}
}
