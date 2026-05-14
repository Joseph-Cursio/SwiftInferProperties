import Foundation
import SwiftInferCore

/// V1.42.C.5 — implicit reindex on demand for `swift-infer verify`.
///
/// The v1.42 plan's C.5 sub-step: when the conventional
/// `.swiftinfer/index.json` is missing or stale, `verify` rebuilds it
/// before the suggestion lookup instead of dead-ending on a
/// `.indexMissing` error or surveying a stale surface. Extracted to its
/// own file in V1.42.C.5 so `VerifyCommand.swift` stays near its prior
/// length.
extension SwiftInferCommand.Verify {

    /// Rebuild the conventional index from a whole-`Sources/` discover
    /// pass when it's missing or stale, before a verify lookup.
    ///
    /// - An explicit `--index-path` is used as-is — the user pointed at
    ///   a specific file, so it's never auto-rebuilt.
    /// - A package with no `Sources/` directory is left alone: the
    ///   pre-V1.42.C.5 `.indexMissing` / `.indexEmpty` error path still
    ///   applies (there's nothing to scan).
    /// - Reindex progress + the index summary go to `diagnostics`
    ///   (stderr in production) — `verify`'s stdout is the outcome /
    ///   JSON stream and must stay clean.
    static func reindexIfNeeded(
        packageRoot: URL,
        explicitIndexPath: URL?,
        diagnostics: any DiagnosticOutput = PrintDiagnosticOutput()
    ) throws {
        guard explicitIndexPath == nil else { return }
        let indexPath = IndexStore.defaultPath(for: packageRoot)
        let exists = FileManager.default.fileExists(atPath: indexPath.path)
        let stale = exists
            && VerifyHarness.isStale(indexPath: indexPath, packageRoot: packageRoot)
        guard !exists || stale else { return }
        let sources = packageRoot.appendingPathComponent("Sources")
        guard FileManager.default.fileExists(atPath: sources.path) else { return }
        diagnostics.writeDiagnostic(
            "index \(exists ? "stale" : "missing") — reindexing \(sources.path) "
                + "before lookup (V1.42.C.5)"
        )
        let (_, summary) = try SwiftInferCommand.Index.performIndex(
            IndexInputs(
                scanDirectory: sources,
                includePossible: true,
                explicitVocabularyPath: nil,
                explicitConfigPath: nil,
                explicitTestDirPath: nil,
                packsOverride: nil,
                dryRun: false
            ),
            diagnostics: diagnostics
        )
        diagnostics.writeDiagnostic(summary)
    }
}
