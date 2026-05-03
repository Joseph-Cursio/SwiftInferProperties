import Foundation
import SwiftInferCLI
import SwiftInferTestLifter
import Testing

/// PRD v0.4 §13 performance budget enforcement for TestLifter — the
/// "TestLifter parse of 100 test files" row mandates `< 3 seconds wall`.
/// A regression test failure blocks release per PRD §13 conventions.
///
/// M2.4 widens the synthetic corpus to include all three M1+M2
/// detector shapes (round-trip, idempotence, commutativity) so the
/// budget check exercises the full detector fan-out, not just the
/// round-trip pass. Real-world test corpora carry a mix of patterns;
/// budgeting against the mix is more representative.
@Suite("TestLifter — PRD §13 100-test-file budget (M1.6 + M2.4)")
struct TestLifterPerformanceTests {

    @Test("TestLifter.discover on 100 synthetic test files completes in < 3s wall")
    func syntheticHundredTestFileCorpus() throws {
        let directory = try generateSyntheticTestCorpus(fileCount: 100)
        defer { try? FileManager.default.removeItem(at: directory) }

        var artifacts: TestLifter.Artifacts = .empty
        let elapsed = try measureWall {
            artifacts = try TestLifter.discover(in: directory)
        }
        #expect(
            elapsed < 3.0,
            "TestLifter.discover on 100 test files took \(formatted(elapsed))s — over the §13 3s budget"
        )
        // Each file contributes one round-trip + one idempotence + one
        // commutativity test body, so the discover pass should produce
        // ~300 lifted suggestions. Assert >= 200 for headroom against
        // future detector tightening; assert per-template surface to
        // confirm all three detectors are wired through end-to-end.
        #expect(
            artifacts.liftedSuggestions.count >= 200,
            "TestLifter surfaced only \(artifacts.liftedSuggestions.count) lifted suggestions on a 100-file corpus"
        )
        let templateCounts = Dictionary(
            grouping: artifacts.liftedSuggestions,
            by: \.templateName
        ).mapValues(\.count)
        #expect((templateCounts["round-trip"] ?? 0) >= 50, "round-trip detector contributed too few suggestions")
        #expect((templateCounts["idempotence"] ?? 0) >= 50, "idempotence detector contributed too few suggestions")
        #expect((templateCounts["commutativity"] ?? 0) >= 50, "commutativity detector contributed too few suggestions")
    }

    /// M3.4 §13 perf re-check: the M3.2 pipeline pass adds promotion +
    /// type recovery + GeneratorSelection + suppression on top of the
    /// existing TestLifter parse. Verifies the additional work stays
    /// within a budget that's still useful for v0.1.0+ users — the
    /// upper bound is set at `< 5s wall` for the 100-test-file corpus
    /// (parse pass alone is already budgeted at < 3s; the M3.2
    /// pipeline overhead must be sub-second to keep the headroom).
    /// A regression beyond this would suggest the M3.2 pipeline pass
    /// has algorithmic issues worth investigating before shipping.
    @Test("Discover pipeline (CLI) on 100 test files stays under 5s with M3.2 lifted-pipeline pass active")
    func discoverPipelineHundredTestFileBudgetWithM32Pipeline() throws {
        let directory = try generateSyntheticTestCorpus(fileCount: 100)
        defer { try? FileManager.default.removeItem(at: directory) }

        var pipelineResult: SwiftInferCommand.Discover.PipelineResult?
        let elapsed = try measureWall {
            pipelineResult = try SwiftInferCommand.Discover.collectVisibleSuggestions(
                directory: directory,
                includePossible: true,
                diagnostics: SilentPerfDiagnostics()
            )
        }
        #expect(
            elapsed < 5.0,
            """
            Discover pipeline on 100 test files took \(formatted(elapsed))s — \
            over the M3.4 5s budget (parse < 3s + M3.2 overhead headroom)
            """
        )
        // The M3.2 pipeline should produce at least 200 promoted lifted
        // suggestions (matching the lifted-only assertion in
        // syntheticHundredTestFileCorpus). Confirms the pipeline is
        // actually doing the promotion work, not bypassing it.
        let suggestions = pipelineResult?.suggestions ?? []
        #expect(
            suggestions.count >= 200,
            "Discover pipeline surfaced only \(suggestions.count) suggestions on a 100-file corpus"
        )
    }

    // MARK: - Synthetic corpus

    private func generateSyntheticTestCorpus(fileCount: Int) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInferTestLifterPerf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        for index in 0..<fileCount {
            let url = base.appendingPathComponent("FooTests\(index).swift")
            try syntheticTestFileSource(index: index)
                .write(to: url, atomically: true, encoding: .utf8)
        }
        return base
    }

    private func syntheticTestFileSource(index: Int) -> String {
        // Per-file unique callee names so per-file CrossValidationKeys
        // are distinct (reflects what real test corpora look like).
        let forward = "encode\(index)"
        let backward = "decode\(index)"
        let unary = "normalize\(index)"
        let binary = "merge\(index)"
        return """
        import XCTest
        import Testing

        final class FooTests\(index): XCTestCase {
            func testRoundTripExplicit() {
                let original = MyData()
                let encoded = \(forward)(original)
                let decoded = \(backward)(encoded)
                XCTAssertEqual(original, decoded)
            }

            func testRoundTripCollapsed() {
                let original = MyData()
                XCTAssertEqual(\(backward)(\(forward)(original)), original)
            }

            func testIdempotent() {
                let s = "hello"
                let once = \(unary)(s)
                let twice = \(unary)(once)
                XCTAssertEqual(once, twice)
            }

            func testCommutative() {
                let a = [1, 2]
                let b = [3, 4]
                XCTAssertEqual(\(binary)(a, b), \(binary)(b, a))
            }

            func testNonDetectableHelper() {
                let result = helper()
                XCTAssertNotNil(result)
            }
        }

        @Test func swiftTestingRoundTrip\(index)() {
            let original = MyData()
            #expect(\(backward)(\(forward)(original)) == original)
        }
        """
    }

    // MARK: - Wall-clock measurement

    private func measureWall(_ block: () throws -> Void) rethrows -> Double {
        let start = Date()
        try block()
        return Date().timeIntervalSince(start)
    }

    private func formatted(_ seconds: Double) -> String {
        String(format: "%.3f", seconds)
    }
}

/// Silent diagnostic sink for the M3.4 pipeline-budget test —
/// suppresses ConfigLoader / VocabularyLoader warnings the synthetic
/// fixtures would surface, since they're unrelated to perf
/// measurement.
private struct SilentPerfDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_ message: String) {}
}
