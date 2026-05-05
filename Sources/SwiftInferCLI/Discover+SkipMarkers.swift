import Foundation
import SwiftInferCore

/// Skip-marker filtering helpers for `swift-infer discover`. Split out
/// of `Discover+Pipeline.swift` to keep that file under SwiftLint's
/// 400-line cap (M11.2's `equivalenceClassHintsByIdentity` plumbing
/// crossed the threshold).
extension SwiftInferCommand.Discover {

    /// TestLifter M6.1 — apply `// swiftinfer: skip <hash>` filtering
    /// to the promoted lifted suggestions. The TE side already
    /// filtered against production-target markers inside
    /// `discoverArtifacts`; the lifted side needs both (a) the same
    /// production-target markers re-scanned (since `discoverArtifacts`
    /// doesn't expose them) AND (b) any markers in the resolved test
    /// directory. The user can put `// swiftinfer: skip <lifted-hash>`
    /// in either place to suppress a lifted suggestion.
    static func applyLiftedSkipMarkerFilter(
        to promotedLifted: [Suggestion],
        productionTarget: URL,
        testDirectory: URL,
        diagnostics: any DiagnosticOutput
    ) -> [Suggestion] {
        let liftedSkipHashes = collectLiftedSkipHashes(
            productionTarget: productionTarget,
            testDirectory: testDirectory,
            diagnostics: diagnostics
        )
        if liftedSkipHashes.isEmpty {
            return promotedLifted
        }
        return promotedLifted.filter { suggestion in
            !liftedSkipHashes.contains(suggestion.identity.normalized)
        }
    }

    /// Union of `// swiftinfer: skip <hash>` markers found in the
    /// production-target tree + the resolved test directory tree
    /// (when the two are distinct). The union feeds the
    /// post-promotion filter that suppresses lifted suggestions the
    /// user marked for skip. Errors during the scan are logged to
    /// diagnostics and the partial result is returned — same posture
    /// `discoverArtifacts` takes for its prod-target scan.
    static func collectLiftedSkipHashes(
        productionTarget: URL,
        testDirectory: URL,
        diagnostics: any DiagnosticOutput
    ) -> Set<String> {
        var hashes: Set<String> = []
        do {
            hashes.formUnion(try SkipMarkerScanner.skipHashes(in: productionTarget))
        } catch {
            diagnostics.writeDiagnostic(
                "warning: failed to scan production target for // swiftinfer: skip"
                    + " markers: \(error.localizedDescription)"
            )
        }
        if testDirectory.standardizedFileURL != productionTarget.standardizedFileURL {
            do {
                hashes.formUnion(try SkipMarkerScanner.skipHashes(in: testDirectory))
            } catch {
                diagnostics.writeDiagnostic(
                    "warning: failed to scan test directory for // swiftinfer: skip"
                        + " markers: \(error.localizedDescription)"
                )
            }
        }
        return hashes
    }

    /// Walk up parent directories looking for `Package.swift`. Same
    /// shape as `ConfigLoader.findPackageRoot` /
    /// `VocabularyLoader.findPackageRoot` — kept as a private helper
    /// here so the three resolvers stay independent (each can be
    /// invoked in isolation by tests without setting up the others'
    /// fixture trees).
    static func findPackageRootForTestDir(startingFrom directory: URL) -> URL? {
        let fileManager = FileManager.default
        var current = directory.standardizedFileURL
        while true {
            let manifest = current.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: manifest.path) {
                return current
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent == current {
                return nil
            }
            current = parent
        }
    }
}
