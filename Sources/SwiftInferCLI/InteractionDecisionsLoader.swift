import Foundation
import SwiftInferCore

/// V2.0 — disk-resident decisions lookup for the interaction-invariant
/// accept-flow: `accept-interaction --decisions <path>` and
/// `accept-check-interaction --decisions <path>`. Resolves
/// `.swiftinfer/interaction-decisions.json`.
///
/// The load/write behaviour lives in ``JSONArtifactStore``, shared with the
/// four sibling artifacts; what stays here is the name `Result.decisions`,
/// which callers read.
public enum InteractionDecisionsLoader {

    public struct Result: Equatable {
        public let decisions: InteractionDecisions
        public let warnings: [String]
        public let packageRoot: URL?

        public init(decisions: InteractionDecisions, warnings: [String], packageRoot: URL?) {
            self.decisions = decisions
            self.warnings = warnings
            self.packageRoot = packageRoot
        }
    }

    public static let conventionalRelativePath = InteractionDecisions.conventionalRelativePath

    public static func load(
        startingFrom directory: URL,
        explicitPath: URL? = nil
    ) -> Result {
        let result = Store.load(
            startingFrom: directory,
            explicitPath: explicitPath
        )
        return Result(
            decisions: result.artifact,
            warnings: result.warnings,
            packageRoot: result.packageRoot
        )
    }

    public static func write(_ decisions: InteractionDecisions, to path: URL) throws {
        try Store.write(decisions, to: path)
    }

    public static func defaultPath(for packageRoot: URL) -> URL {
        Store.defaultPath(for: packageRoot)
    }

    private typealias Store = JSONArtifactStore<InteractionDecisions>
}
