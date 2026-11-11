import Foundation
import SwiftInferCore

/// Disk-resident baseline lookup for `swift-infer drift` (M6.5).
/// Resolves `.swiftinfer/baseline.json` per PRD §5.8 M6.
///
/// 1. **Explicit override** — `drift --baseline <path>`. Missing or
///    malformed file produces a warning.
/// 2. **Implicit lookup** — walk up from the discover target's
///    directory to find `Package.swift`, then read
///    `<package-root>/.swiftinfer/baseline.json`. Missing file is
///    silent; malformed file warns and falls back to `Baseline.empty`.
///
/// The load/write behaviour lives in ``JSONArtifactStore``, shared with the
/// four sibling artifacts; what stays here is the name `Result.baseline`,
/// which callers read.
public enum BaselineLoader {

    public struct Result: Equatable {
        public let baseline: Baseline
        public let warnings: [String]
        public let packageRoot: URL?

        public init(baseline: Baseline, warnings: [String], packageRoot: URL?) {
            self.baseline = baseline
            self.warnings = warnings
            self.packageRoot = packageRoot
        }
    }

    /// The baseline's path relative to the package root: `.swiftinfer/baseline.json`.
    public static let conventionalRelativePath = Baseline.conventionalRelativePath

    /// Loads the baseline from `explicitPath` or the package root above `directory`; missing is empty.
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
            baseline: result.artifact,
            warnings: result.warnings,
            packageRoot: result.packageRoot
        )
    }

    /// Writes `baseline` to `path` as canonical JSON, creating `.swiftinfer/` if needed.
    public static func write(_ baseline: Baseline, to path: URL) throws {
        try Store.write(baseline, to: path)
    }

    /// The baseline's path under `packageRoot`.
    public static func defaultPath(for packageRoot: URL) -> URL {
        Store.defaultPath(for: packageRoot)
    }

    private typealias Store = JSONArtifactStore<Baseline>
}
