import Foundation
import SwiftInferCore

/// V2.0 M10 — disk-resident baseline lookup for `swift-infer
/// drift-interaction`. Resolves `.swiftinfer/interaction-baseline.json`.
///
/// The load/write behaviour lives in ``JSONArtifactStore``, shared with the
/// four sibling artifacts; what stays here is the name `Result.baseline`,
/// which callers read.
public enum InteractionBaselineLoader {

    public struct Result: Equatable {
        public let baseline: InteractionBaseline
        public let warnings: [String]
        public let packageRoot: URL?

        public init(baseline: InteractionBaseline, warnings: [String], packageRoot: URL?) {
            self.baseline = baseline
            self.warnings = warnings
            self.packageRoot = packageRoot
        }
    }

    public static let conventionalRelativePath = InteractionBaseline.conventionalRelativePath

    public static func load(
        startingFrom directory: URL,
        explicitPath: URL? = nil
    ) -> Result {
        let result = Store.load(
            startingFrom: directory,
            explicitPath: explicitPath
        )
        return Result(
            baseline: result.artifact,
            warnings: result.warnings,
            packageRoot: result.packageRoot
        )
    }

    public static func write(_ baseline: InteractionBaseline, to path: URL) throws {
        try Store.write(baseline, to: path)
    }

    public static func defaultPath(for packageRoot: URL) -> URL {
        Store.defaultPath(for: packageRoot)
    }

    private typealias Store = JSONArtifactStore<InteractionBaseline>
}
