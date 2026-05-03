import Foundation
import Testing
import SwiftInferCLI
import SwiftInferCore

/// PRD v0.4 §13 row 5 — `swift-infer discover --interactive` must
/// reach the first prompt in < 1s after process start. The row had
/// no regression test before R1.1.c. The test drives `Discover.run`
/// with a `PromptInput` stub that records the wall-clock time of its
/// first `readLine()` call and asserts the elapsed time from
/// `Discover.run` entry to that point stays inside the 1s budget.
///
/// **Endpoint.** PRD wording is "after process start"; the test
/// times from `Discover.run` entry. The `main` → `AsyncParsableCommand`
/// dispatch overhead between process start and `Discover.run` entry
/// is < 10ms in practice and is not testable from inside the package
/// — open decision #2 in `docs/v1.0 Release Plan.md`.
///
/// R1.1.c — closes the §13 row 5 gap before the v1.0 cut.
@Suite("Performance — PRD §13 --interactive first-prompt budget (R1.1.c)")
struct InteractiveFirstPromptPerformanceTests {

    @Test("--interactive first prompt fires within the §13 1s budget")
    func firstPromptWithinBudget() throws {
        let packageRoot = try makePackageRoot()
        defer { try? FileManager.default.removeItem(at: packageRoot) }

        let target = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("Lib")
        try writeSyntheticCorpus(at: target, fileCount: 5)

        let prompt = TimingPromptInput()
        let start = Date()
        try SwiftInferCommand.Discover.run(
            directory: target,
            interactive: true,
            promptInput: prompt,
            output: SilentOutput(),
            diagnostics: SilentDiagnosticOutput()
        )
        let firstPromptAt = try #require(
            prompt.firstPromptTimestamp(),
            "Interactive triage finished without invoking PromptInput.readLine() — the synthetic corpus produced no triagable suggestions"
        )
        let elapsed = firstPromptAt.timeIntervalSince(start)
        #expect(
            elapsed < 1.0,
            "First --interactive prompt fired \(formatted(elapsed))s after Discover.run entry — over the §13 1s budget"
        )
    }

    // MARK: - Synthetic corpus

    private func makePackageRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInferInteractivePerf-\(UUID().uuidString)")
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
        // Round-trip pair fires the round-trip template at Strong tier
        // — guaranteed to surface at least one triagable suggestion.
        """
        import Foundation

        struct Payload\(index) {}
        struct Data\(index) {}

        struct Container\(index) {
            func encode(_ value: Payload\(index)) -> Data\(index) {
                return Data\(index)()
            }
            func decode(_ data: Data\(index)) -> Payload\(index) {
                return Payload\(index)()
            }
        }
        """
    }

    private func formatted(_ seconds: Double) -> String {
        String(format: "%.3f", seconds)
    }
}

// MARK: - Timing PromptInput

/// `PromptInput` that records the wall-clock time of its first
/// `readLine()` call and answers `n` (skip) thereafter to drive the
/// triage loop to completion without writing files.
private final class TimingPromptInput: PromptInput, @unchecked Sendable {

    private let lock = NSLock()
    private var firstAt: Date?

    func readLine() -> String? {
        lock.lock()
        if firstAt == nil { firstAt = Date() }
        lock.unlock()
        return "n"
    }

    func firstPromptTimestamp() -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return firstAt
    }
}

// MARK: - Silent stubs

private final class SilentOutput: DiscoverOutput, @unchecked Sendable {
    func write(_ text: String) {}
}

private final class SilentDiagnosticOutput: DiagnosticOutput, @unchecked Sendable {
    func writeDiagnostic(_ text: String) {}
}
