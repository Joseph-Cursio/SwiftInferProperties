import Foundation
import Testing
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates

/// PRD v0.4 §13 row 3 — `swift-infer drift` re-run after one-file
/// change must complete in < 500ms (incremental). The drift command
/// currently does a full discover scan + baseline diff (no caching);
/// the budget asserts that on a typical small project the full scan
/// fits inside the latency budget the PRD documents.
///
/// R1.1.a — closes the §13 row 3 gap before the v0.1.0 cut.
@Suite("Performance — PRD §13 drift incremental budget (R1.1.a)")
struct DriftIncrementalPerformanceTests {

    /// 10-file synthetic corpus. Pre-discover → write a baseline
    /// matching the surfaced suggestions → touch one file → run drift
    /// and assert the second run completes in < 500ms wall.
    @Test("Drift re-run after one-file change completes within the §13 500ms budget")
    func driftReRunWithinBudget() throws {
        let packageRoot = try makePackageRoot()
        defer { try? FileManager.default.removeItem(at: packageRoot) }

        let target = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("Lib")
        try writeSyntheticCorpus(at: target, fileCount: 10)

        let pipeline = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: target,
            diagnostics: SilentDiagnosticOutput()
        )
        let baseline = Baseline(entries: pipeline.suggestions.map { suggestion in
            BaselineEntry(
                identityHash: suggestion.identity.normalized,
                template: suggestion.templateName,
                scoreAtSnapshot: suggestion.score.total,
                tier: suggestion.score.tier
            )
        })
        try BaselineLoader.write(
            baseline,
            to: BaselineLoader.defaultPath(for: packageRoot)
        )

        let touched = target.appendingPathComponent("File0.swift")
        let original = try String(contentsOf: touched, encoding: .utf8)
        try (original + "\n// touched\n").write(to: touched, atomically: true, encoding: .utf8)

        let elapsed = try measureWall {
            try SwiftInferCommand.Drift.run(
                directory: target,
                output: SilentOutput(),
                diagnostics: SilentDiagnosticOutput()
            )
        }

        #expect(
            elapsed < 0.5,
            "Drift re-run took \(formatted(elapsed))s — over the §13 500ms budget"
        )
    }

    // MARK: - Synthetic corpus

    private func makePackageRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInferDriftPerf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 6.1\n".utf8).write(
            to: root.appendingPathComponent("Package.swift")
        )
        return root
    }

    private func writeSyntheticCorpus(at directory: URL, fileCount: Int) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        for index in 0..<fileCount {
            let url = directory.appendingPathComponent("File\(index).swift")
            try syntheticFileSource(index: index)
                .write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func syntheticFileSource(index: Int) -> String {
        """
        import Foundation

        struct Payload\(index) {}
        struct Data\(index) {}

        struct Container\(index) {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
            func encode(_ value: Payload\(index)) -> Data\(index) {
                return Data\(index)()
            }
            func decode(_ data: Data\(index)) -> Payload\(index) {
                return Payload\(index)()
            }
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

// MARK: - Silent stubs

private final class SilentOutput: DiscoverOutput, @unchecked Sendable {
    func write(_ text: String) {}
}

private final class SilentDiagnosticOutput: DiagnosticOutput, @unchecked Sendable {
    func writeDiagnostic(_ text: String) {}
}
