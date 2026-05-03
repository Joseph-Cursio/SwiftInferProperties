import Foundation
import Testing
import SwiftInferCLI
import SwiftInferCore

/// PRD v0.4 §16 #3 hard guarantee — "SwiftInfer never auto-accepts
/// suggestions. Even in CI mode, `drift` emits warnings, not
/// failures. The accept/reject step is always human." The contract
/// was implicitly covered by existing `DriftCommandTests` (every
/// test calls `try Drift.run(...)` and the absence of `throws`
/// surfaces means the process would exit 0) but had no explicit
/// release-gate test pinning the contract under heavy divergence.
///
/// R1.1.e — closes the §16 #3 gap before the v0.1.0 cut.
@Suite("Drift — PRD §16 #3 never fails CI (R1.1.e)")
struct DriftNeverFailsCITests {

    /// Constructs a synthetic project with multiple Strong-tier
    /// suggestions that all drift against an empty baseline (so the
    /// "every Strong is new" path fires for every suggestion). Asserts:
    /// - `Drift.run` does not throw
    /// - Drift warnings are emitted (the path is exercised)
    /// - Output line reports the warning count (the success-with-
    ///   warnings shape PRD §3 + §9 prescribe)
    /// - No fatal-style "error:" prefix appears in diagnostics
    @Test("Heavy drift surface emits warnings without failing the process (PRD §16 #3)")
    func heavyDriftEmitsWarningsButDoesNotFail() throws {
        let packageRoot = try makePackageRoot()
        defer { try? FileManager.default.removeItem(at: packageRoot) }

        let target = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("Lib")
        try writeSyntheticCorpus(at: target, fileCount: 5)

        let output = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()

        // No baseline → every Strong-tier suggestion drifts. This is
        // the heaviest realistic divergence — far more drift signal
        // than a typical PR — and the §16 #3 contract still requires
        // a clean (no-throw, no-error) return.
        try SwiftInferCommand.Drift.run(
            directory: target,
            output: output,
            diagnostics: diagnostics
        )

        let driftWarnings = diagnostics.lines.filter { $0.hasPrefix("warning: drift:") }
        #expect(
            !driftWarnings.isEmpty,
            "Heavy-divergence fixture produced no drift warnings — the §16 #3 path was not exercised"
        )

        let countLine = output.lines.first { $0.contains("drift warning") }
        let counted = try #require(
            countLine,
            "Drift output did not include the warning-count line PRD §3 + §9 prescribe"
        )
        #expect(
            counted.hasSuffix(" emitted."),
            "Drift output line did not match the success-with-warnings shape: \(counted)"
        )

        // §16 #3 forbids drift from raising fatal-style failures.
        // Diagnostics may contain warnings (drift lines + load
        // warnings) but never an `error:` prefix that CI runners
        // would interpret as a build failure.
        let errorLines = diagnostics.lines.filter { $0.hasPrefix("error:") }
        #expect(
            errorLines.isEmpty,
            "Drift emitted error-prefixed lines, violating §16 #3: \(errorLines)"
        )
    }

    // MARK: - Synthetic corpus

    private func makePackageRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInferDriftCI-\(UUID().uuidString)")
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
        // Round-trip + idempotence per file = at least 2 Strong-tier
        // suggestions per file × 5 files = 10+ drift warnings.
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
}

// MARK: - Recording stubs

private final class RecordingOutput: DiscoverOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [String] = []
    var lines: [String] {
        lock.lock(); defer { lock.unlock() }
        return captured
    }
    func write(_ text: String) {
        lock.lock(); captured.append(text); lock.unlock()
    }
}

private final class RecordingDiagnosticOutput: DiagnosticOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [String] = []
    var lines: [String] {
        lock.lock(); defer { lock.unlock() }
        return captured
    }
    func writeDiagnostic(_ text: String) {
        lock.lock(); captured.append(text); lock.unlock()
    }
}
