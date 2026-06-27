import Foundation
import SwiftInferCore

/// V1.143 — disk store for the durable replay corpus
/// (`.swiftinfer/verify-corpus.json`). A near-sibling of
/// `VerifyEvidenceStore`, but with **accumulate** semantics
/// (`VerifyCorpus.adding`) rather than upsert-latest: the corpus keeps every
/// distinct counterexample as a permanent regression guard.
///
/// Reuses `VerifyEvidenceStore`'s canonical encoder/decoder (sorted-keys +
/// pretty + ISO8601) so the two `.swiftinfer/*.json` artifacts diff
/// identically. The read path never throws (missing → empty silent; malformed
/// → empty + warning); `write` IS throwing (an explicit persistence gesture);
/// `record` is best-effort (write failure → warning).
public enum VerifyCorpusStore {

    public static let conventionalRelativePath = ".swiftinfer/verify-corpus.json"

    public static func defaultPath(for packageRoot: URL) -> URL {
        packageRoot.appendingPathComponent(conventionalRelativePath)
    }

    /// Load the corpus beneath `packageRoot`. Missing file → `.empty`
    /// (silent — the corpus accumulates across runs); malformed → `.empty`
    /// plus a warning.
    public static func load(packageRoot: URL) -> (corpus: VerifyCorpus, warnings: [String]) {
        let path = defaultPath(for: packageRoot)
        guard FileManager.default.fileExists(atPath: path.path) else { return (.empty, []) }
        do {
            let data = try Data(contentsOf: path)
            let corpus = try VerifyEvidenceStore.canonicalDecoder.decode(VerifyCorpus.self, from: data)
            var warnings: [String] = []
            if corpus.schemaVersion > VerifyCorpus.currentSchemaVersion {
                warnings.append(
                    "verify-corpus at \(path.path): schemaVersion \(corpus.schemaVersion) "
                        + "is newer than v\(VerifyCorpus.currentSchemaVersion); loading what we can"
                )
            }
            return (corpus, warnings)
        } catch {
            return (.empty, ["could not parse verify-corpus at \(path.path): \(error)"])
        }
    }

    /// Write `corpus` atomically, creating `.swiftinfer/` if needed.
    public static func write(_ corpus: VerifyCorpus, to path: URL) throws {
        let data = try VerifyEvidenceStore.canonicalEncoder.encode(corpus)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: path, options: .atomic)
    }

    /// Accumulate `entry` into the corpus at `packageRoot` (load → add → write).
    /// Best-effort: a write failure returns a warning rather than throwing into
    /// the verify gesture. Returns any load + write warnings.
    public static func record(_ entry: VerifyCorpusEntry, packageRoot: URL) -> [String] {
        recordBatch([entry], packageRoot: packageRoot)
    }

    /// Accumulate a batch of entries in a single load → fold-`adding` → write.
    /// Used by `--all-from-index` survey mode, where per-entry writes during
    /// the parallel loop would race. Empty batch is a no-op.
    public static func recordBatch(_ entries: [VerifyCorpusEntry], packageRoot: URL) -> [String] {
        guard entries.isEmpty == false else { return [] }
        let (existing, warnings) = load(packageRoot: packageRoot)
        var result = warnings
        let corpus = entries.reduce(existing) { $0.adding($1) }
        let path = defaultPath(for: packageRoot)
        do {
            try write(corpus, to: path)
        } catch {
            result.append("could not write verify-corpus to \(path.path): \(error.localizedDescription)")
        }
        return result
    }
}
