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

    public static let conventionalRelativePath = Decisions.conventionalRelativePath

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

    public static func write(_ decisions: Decisions, to path: URL) throws {
        try Store.write(decisions, to: path)
    }

    public static func defaultPath(for packageRoot: URL) -> URL {
        Store.defaultPath(for: packageRoot)
    }

    private typealias Store = JSONArtifactStore<Decisions>
}
