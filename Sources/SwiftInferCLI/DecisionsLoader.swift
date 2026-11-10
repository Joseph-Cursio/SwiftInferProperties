import Foundation
import SwiftInferCore

/// Disk-resident decisions lookup for `swift-infer discover --interactive`
/// + `swift-infer drift`. Resolves `.swiftinfer/decisions.json` per PRD §5.8
/// M6. A missing file is silent — decisions are opt-in and accumulate over
/// time, so absence is the normal state rather than a fault.
///
/// The load/write behaviour lives in ``JSONArtifactStore``, shared with the
/// four sibling artifacts; what stays here is the name `Result.decisions`,
/// which callers read.
public enum DecisionsLoader {

    public struct Result: Equatable {
        public let decisions: Decisions
        public let warnings: [String]
        public let packageRoot: URL?

        public init(decisions: Decisions, warnings: [String], packageRoot: URL?) {
            self.decisions = decisions
            self.warnings = warnings
            self.packageRoot = packageRoot
        }
    }

    /// The decisions file's path relative to the package root: `.swiftinfer/decisions.json`.
    public static let conventionalRelativePath = Decisions.conventionalRelativePath

    /// Loads decisions from `explicitPath` or the package root above `directory`; missing is empty.
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
            decisions: result.artifact,
            warnings: result.warnings,
            packageRoot: result.packageRoot
        )
    }

    /// Writes `decisions` to `path` as canonical JSON, creating `.swiftinfer/` if needed.
    public static func write(_ decisions: Decisions, to path: URL) throws {
        try Store.write(decisions, to: path)
    }

    /// The decisions file's path under `packageRoot`.
    public static func defaultPath(for packageRoot: URL) -> URL {
        Store.defaultPath(for: packageRoot)
    }

    private typealias Store = JSONArtifactStore<Decisions>
}
