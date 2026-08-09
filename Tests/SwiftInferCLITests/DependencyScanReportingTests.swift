import Foundation
@testable import SwiftInferCLI
import Testing

/// An empty dependency scan used to be unreadable in three different ways — no `.build`,
/// an unreadable checkout, a checkout with no types — and the caller saw one
/// undifferentiated empty map.
///
/// **This is not hypothetical.** Three `--scan-dependencies` surveys returned output
/// byte-identical to runs without the flag, and the only reason it was caught is that an
/// unrelated control happened to print the shape count. With reporting, the first run named
/// the cause in one line.
@Suite("Dependency scan — an empty result says which empty it is")
struct DependencyScanReportingTests {

    private final class Recorder: DiagnosticOutput, @unchecked Sendable {
        var lines: [String] = []

        func writeDiagnostic(_ message: String) { lines.append(message) }
    }

    private func merge(at root: URL) -> [String] {
        let recorder = Recorder()
        _ = DependencyTypeShapes.merging(
            shapes: [:], sourceFiles: [:], localTypeNames: [],
            packageRoot: root, diagnostics: recorder
        )
        return recorder.lines
    }

    /// The measured case: a fresh `git worktree` has no `.build`, so the scan reads nothing
    /// — and said nothing.
    @Test("no .build/checkouts is reported, not swallowed")
    func missingCheckoutsIsReported() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dep-scan-none-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let lines = merge(at: tmp)
        #expect(lines.contains { $0.contains("no `.build/checkouts`") })
        #expect(lines.contains { $0.contains("0 dependency shape(s) recorded") })
        #expect(lines.contains { $0.contains("swift build") }, "the reader needs the remedy")
    }

    /// Present but empty is a *different* fact from absent, and must read differently.
    @Test("a checkouts directory with no readable Sources is reported distinctly")
    func emptyCheckoutsIsReportedDistinctly() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dep-scan-empty-\(UUID().uuidString)")
        let checkouts = tmp.appendingPathComponent(".build").appendingPathComponent("checkouts")
        try FileManager.default.createDirectory(at: checkouts, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let lines = merge(at: tmp)
        #expect(lines.contains { $0.contains("no checkout has a readable `Sources`") })
        #expect(
            !lines.contains { $0.contains("no `.build/checkouts`") },
            "present-but-empty must not report as absent — that is the distinction"
        )
    }

    /// **The guard on the guard.** A reporter that says nothing in every case would pass the
    /// two arms above only by accident of their `contains` checks; assert it speaks at all.
    @Test("the scan always says something when asked")
    func scanIsNeverSilent() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dep-scan-silent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(!merge(at: tmp).isEmpty)
    }
}
