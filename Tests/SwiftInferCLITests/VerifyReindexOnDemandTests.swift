import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// V1.42.C.5 — implicit reindex on demand. `IndexCommand.performIndex`
// is the discover → project → upsert → save pipeline hoisted into a
// callable static; `Verify.reindexIfNeeded` drives it before a verify
// lookup when the conventional `.swiftinfer/index.json` is missing or
// stale. An explicit `--index-path`, or a package with no `Sources/`,
// is left alone.
@Suite("Verify — V1.42.C.5 implicit reindex on demand")
struct VerifyReindexOnDemandTests {

    private final class RecordingDiag: DiagnosticOutput, @unchecked Sendable {
        private(set) var lines: [String] = []

        func writeDiagnostic(_ text: String) { lines.append(text) }
    }

    /// A minimal SwiftPM package fixture with one recursive-idempotence
    /// function under `Sources/Lib/`. When `withIndex` is set, a fresh
    /// index is built (so it post-dates the sources and reads as
    /// non-stale).
    private func makePackageFixture(name: String, withIndex: Bool) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VerifyReindex-\(name)-\(UUID().uuidString)")
        let sources = root.appendingPathComponent("Sources").appendingPathComponent("Lib")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: root.appendingPathComponent("Package.swift"))
        try """
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """.write(
            to: sources.appendingPathComponent("Source.swift"),
            atomically: true,
            encoding: .utf8
        )
        if withIndex {
            _ = try SwiftInferCommand.Index.performIndex(
                IndexInputs(
                    scanDirectory: root.appendingPathComponent("Sources"),
                    includePossible: true,
                    explicitVocabularyPath: nil,
                    explicitConfigPath: nil,
                    explicitTestDirPath: nil,
                    packsOverride: nil,
                    dryRun: false
                ),
                diagnostics: RecordingDiag()
            )
        }
        return root
    }

    private func indexPath(in root: URL) -> URL {
        IndexStore.defaultPath(for: root)
    }

    // MARK: - performIndex

    @Test("performIndex writes an index built from a whole-Sources scan")
    func performIndexWritesIndex() throws {
        let root = try makePackageFixture(name: "perform", withIndex: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let (index, summary) = try SwiftInferCommand.Index.performIndex(
            IndexInputs(
                scanDirectory: root.appendingPathComponent("Sources"),
                includePossible: true,
                explicitVocabularyPath: nil,
                explicitConfigPath: nil,
                explicitTestDirPath: nil,
                packsOverride: nil,
                dryRun: false
            ),
            diagnostics: RecordingDiag()
        )
        #expect(!index.entries.isEmpty)
        #expect(index.entries.contains { $0.primaryFunctionName.hasPrefix("normalize") })
        #expect(summary.hasPrefix("Indexed "))
        #expect(FileManager.default.fileExists(atPath: indexPath(in: root).path))
    }

    @Test("performIndex with dryRun reports but writes nothing")
    func performIndexDryRunWritesNothing() throws {
        let root = try makePackageFixture(name: "dryrun", withIndex: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let (_, summary) = try SwiftInferCommand.Index.performIndex(
            IndexInputs(
                scanDirectory: root.appendingPathComponent("Sources"),
                includePossible: true,
                explicitVocabularyPath: nil,
                explicitConfigPath: nil,
                explicitTestDirPath: nil,
                packsOverride: nil,
                dryRun: true
            ),
            diagnostics: RecordingDiag()
        )
        #expect(summary.contains("--dry-run, no write"))
        #expect(!FileManager.default.fileExists(atPath: indexPath(in: root).path))
    }

    // MARK: - reindexIfNeeded

    @Test("reindexIfNeeded rebuilds a missing conventional index")
    func reindexBuildsMissingIndex() throws {
        let root = try makePackageFixture(name: "missing", withIndex: false)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!FileManager.default.fileExists(atPath: indexPath(in: root).path))

        let diagnostics = RecordingDiag()
        try SwiftInferCommand.Verify.reindexIfNeeded(
            packageRoot: root,
            explicitIndexPath: nil,
            diagnostics: diagnostics
        )
        #expect(FileManager.default.fileExists(atPath: indexPath(in: root).path))
        #expect(diagnostics.lines.contains { $0.contains("index missing — reindexing") })
    }

    @Test("reindexIfNeeded is a no-op when a fresh index already exists")
    func reindexNoOpForFreshIndex() throws {
        let root = try makePackageFixture(name: "fresh", withIndex: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try Data(contentsOf: indexPath(in: root))

        let diagnostics = RecordingDiag()
        try SwiftInferCommand.Verify.reindexIfNeeded(
            packageRoot: root,
            explicitIndexPath: nil,
            diagnostics: diagnostics
        )
        // No reindex diagnostic emitted, and the index file is untouched.
        #expect(diagnostics.lines.isEmpty)
        #expect(try Data(contentsOf: indexPath(in: root)) == before)
    }

    @Test("reindexIfNeeded leaves an explicit --index-path alone even when missing")
    func reindexSkipsExplicitPath() throws {
        let root = try makePackageFixture(name: "explicit", withIndex: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let explicit = root.appendingPathComponent("custom-index.json")
        let diagnostics = RecordingDiag()
        try SwiftInferCommand.Verify.reindexIfNeeded(
            packageRoot: root,
            explicitIndexPath: explicit,
            diagnostics: diagnostics
        )
        // Explicit path is used as-is — neither it nor the conventional
        // index is built.
        #expect(!FileManager.default.fileExists(atPath: explicit.path))
        #expect(!FileManager.default.fileExists(atPath: indexPath(in: root).path))
        #expect(diagnostics.lines.isEmpty)
    }

    @Test("reindexIfNeeded is a no-op for a package with no Sources/ directory")
    func reindexNoOpWithoutSourcesDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VerifyReindex-noSources-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: root.appendingPathComponent("Package.swift"))
        defer { try? FileManager.default.removeItem(at: root) }

        let diagnostics = RecordingDiag()
        try SwiftInferCommand.Verify.reindexIfNeeded(
            packageRoot: root,
            explicitIndexPath: nil,
            diagnostics: diagnostics
        )
        // No Sources/ → the pre-V1.42.C.5 `.indexMissing` path still
        // applies; reindexIfNeeded does nothing.
        #expect(!FileManager.default.fileExists(atPath: indexPath(in: root).path))
        #expect(diagnostics.lines.isEmpty)
    }
}
