import Foundation
import SwiftInferCore

/// Disk-resident verify-evidence store for `swift-infer verify` (writer) and
/// `swift-infer discover` (reader — v1.64 workstream C). Resolves
/// `.swiftinfer/verify-evidence.json`. A missing file is silent: evidence is
/// opt-in and accumulates across `verify` runs.
///
/// This file used to argue for being a near-clone of `DecisionsLoader` rather
/// than a shared generic. ``JSONArtifactStore`` reverses that and restates the
/// argument in full, including the half of it that still holds.
///
/// The load/write behaviour lives in ``JSONArtifactStore``, shared with the
/// four sibling artifacts; what stays here is the name `Result.log`, which
/// callers read, and the canonical coders — `VerifyCorpusStore` borrows them
/// so the corpus and the evidence log stay byte-compatible.
public enum VerifyEvidenceStore {

    public struct Result: Equatable {
        public let log: VerifyEvidenceLog
        public let warnings: [String]
        public let packageRoot: URL?

        public init(log: VerifyEvidenceLog, warnings: [String], packageRoot: URL?) {
            self.log = log
            self.warnings = warnings
            self.packageRoot = packageRoot
        }
    }

    public static let conventionalRelativePath = VerifyEvidenceLog.conventionalRelativePath

    public static func load(
        startingFrom directory: URL,
        explicitPath: URL? = nil,
        fileSystem: FileSystemReader = DefaultFileSystemReader()
    ) -> Result {
        let result = Store.load(
            startingFrom: directory,
            explicitPath: explicitPath,
            fileSystem: fileSystem
        )
        return Result(
            log: result.artifact,
            warnings: result.warnings,
            packageRoot: result.packageRoot
        )
    }

    public static func write(_ log: VerifyEvidenceLog, to path: URL) throws {
        try Store.write(log, to: path)
    }

    public static func defaultPath(for packageRoot: URL) -> URL {
        Store.defaultPath(for: packageRoot)
    }

    /// Re-exported because `VerifyCorpusStore` writes a neighbouring file and
    /// must use the identical encoder — same `sortedKeys` + `prettyPrinted`
    /// shape, so the two `.swiftinfer/` artifacts diff the same way.
    static var canonicalEncoder: JSONEncoder { CanonicalJSON.encoder }

    static var canonicalDecoder: JSONDecoder { CanonicalJSON.decoder }

    private typealias Store = JSONArtifactStore<VerifyEvidenceLog>
}
