import Foundation
import SwiftInferCLI
import SwiftInferTestLifter
import Testing

/// PRD v0.4 §13 performance budget enforcement for TestLifter — the
/// "TestLifter parse of 100 test files" row mandates `< 3 seconds wall`.
/// A regression test failure blocks release per PRD §13 conventions.
///
/// M2.4 widened the synthetic corpus to include all three M1+M2
/// detector shapes (round-trip, idempotence, commutativity); M5.6
/// re-widens to all six (adds monotonicity, count-invariance,
/// reduce-equivalence) so the budget check exercises the full M5
/// detector fan-out — not just the M2 trio. Real-world test corpora
/// carry a mix of patterns; budgeting against the mix is more
/// representative.
@Suite("TestLifter — PRD §13 100-test-file budget (M1.6 + M2.4 + M5.6)")
struct TestLifterPerformanceTests {

    @Test("TestLifter.discover on 100 synthetic test files completes in < 3s wall (six detectors)")
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
        // M5.6: each file contributes round-trip + idempotence +
        // commutativity + monotonicity + count-invariance + reduce-
        // equivalence test bodies, so the discover pass should produce
        // ~600 lifted suggestions. Assert >= 400 for headroom against
        // future detector tightening; assert per-template surface to
        // confirm all six detectors are wired through end-to-end.
        #expect(
            artifacts.liftedSuggestions.count >= 400,
            "TestLifter surfaced only \(artifacts.liftedSuggestions.count) lifted suggestions on a 100-file corpus"
        )
        let templateCounts = Dictionary(
            grouping: artifacts.liftedSuggestions,
            by: \.templateName
        ).mapValues(\.count)
        #expect((templateCounts["round-trip"] ?? 0) >= 50, "round-trip detector contributed too few suggestions")
        #expect((templateCounts["idempotence"] ?? 0) >= 50, "idempotence detector contributed too few suggestions")
        #expect((templateCounts["commutativity"] ?? 0) >= 50, "commutativity detector contributed too few suggestions")
        #expect((templateCounts["monotonicity"] ?? 0) >= 50, "monotonicity detector contributed too few suggestions")
        #expect(
            (templateCounts["invariant-preservation"] ?? 0) >= 50,
            "count-invariance detector contributed too few suggestions"
        )
        #expect(
            (templateCounts["associativity"] ?? 0) >= 50,
            "reduce-equivalence detector contributed too few suggestions"
        )
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
        // The M3.2 pipeline should produce at least 400 promoted lifted
        // suggestions (matching the M5.6 lifted-only assertion in
        // syntheticHundredTestFileCorpus — six detectors firing per file).
        // Confirms the pipeline is actually doing the promotion work,
        // not bypassing it.
        let suggestions = pipelineResult?.suggestions ?? []
        #expect(
            suggestions.count >= 400,
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
        let bodyLines = [
            roundTripMethods(index: index),
            idempotentAndCommutativeMethods(index: index),
            m5DetectorMethods(index: index),
            nonDetectableMethod(),
            "}",
            "",
            swiftTestingRoundTripDecl(index: index)
        ].joined(separator: "\n\n")
        return """
        import XCTest
        import Testing

        final class FooTests\(index): XCTestCase {
        \(bodyLines)
        """
    }

    private func roundTripMethods(index: Int) -> String {
        let forward = "encode\(index)"
        let backward = "decode\(index)"
        return """
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
        """
    }

    private func idempotentAndCommutativeMethods(index: Int) -> String {
        let unary = "normalize\(index)"
        let binary = "merge\(index)"
        return """
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
        """
    }

    private func m5DetectorMethods(index: Int) -> String {
        let mono = "score\(index)"
        let count = "filter\(index)"
        let reduce = "combine\(index)"
        return """
            func testMonotonic() {
                let a = 5
                let b = 10
                XCTAssertLessThan(a, b)
                XCTAssertLessThanOrEqual(\(mono)(a), \(mono)(b))
            }

            func testCountInvariance() {
                let xs = [1, 2, 3, 4]
                XCTAssertEqual(\(count)(xs).count, xs.count)
            }

            func testReduceEquivalence() {
                let items = [1, 2, 3]
                XCTAssertEqual(items.reduce(0, \(reduce)), items.reversed().reduce(0, \(reduce)))
            }
        """
    }

    private func nonDetectableMethod() -> String {
        """
            func testNonDetectableHelper() {
                let result = helper()
                XCTAssertNotNil(result)
            }
        """
    }

    private func swiftTestingRoundTripDecl(index: Int) -> String {
        """
        @Test func swiftTestingRoundTrip\(index)() {
            let original = MyData()
            #expect(decode\(index)(encode\(index)(original)) == original)
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
