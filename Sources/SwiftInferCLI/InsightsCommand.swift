import ArgumentParser
import Foundation
import SwiftInferCore

/// V1.143 — `swift-infer insights` subcommand. A read-only, on-demand
/// design pass over `.swiftinfer/index.json`: surfaces types that share an
/// algebraic structure ("you have three monoids — consider unifying them")
/// as author-facing suggestions. See `InsightsBuilder` for the rationale.
///
/// Pull, not push: this is a report you run when you want a design review,
/// not an every-build nag. Gated to `Strong`/`Likely` by default (the
/// Daikon-trap guard); `--include-possible` widens it with a caveat.
extension SwiftInferCommand {

    public struct Insights: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "insights",
            abstract: "Cross-type design suggestions from the SemanticIndex "
                + "(e.g. types sharing a monoid/semigroup shape). Read-only, author-facing."
        )

        @Option(
            name: .long,
            help: "Override the package root for the index walk-up."
        )
        public var directory: String?

        @Option(
            name: .long,
            help: "Path to a specific index file (default: <package-root>/.swiftinfer/index.json)."
        )
        public var indexPath: String?

        @Option(
            name: .long,
            help: "Minimum number of types sharing a structure before it's reported (default: 2)."
        )
        public var minTypes: Int = 2

        @Flag(
            name: .long,
            help: """
            Also consider Possible-tier rows (noisier; off by default — a shared \
            shape at Possible is often coincidence).
            """
        )
        public var includePossible: Bool = false

        public init() { /* no-op */ }

        public func run() {
            let directoryURL = URL(fileURLWithPath: directory ?? ".")
            let explicitIndex = indexPath.map { URL(fileURLWithPath: $0) }
            guard let resolvedIndex = explicitIndex ?? Self.resolveIndexPath(startingFrom: directoryURL) else {
                print("No .swiftinfer/index.json found. Run `swift-infer index --target <X>` first.")
                return
            }
            let now = SwiftInferCommand.Index.isoTimestamp(from: Date())
            let load = IndexStore.load(from: resolvedIndex, nowTimestamp: now)
            for warning in load.warnings {
                FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
            }

            let tiers: Set<String> = includePossible
                ? ["Verified", "Strong", "Likely", "Possible"]
                : ["Verified", "Strong", "Likely"]
            let groups = InsightsBuilder.groups(
                in: load.index,
                minTypes: max(2, minTypes),
                includeTiers: tiers
            )
            print(
                InsightsBuilder.render(groups, minTypes: max(2, minTypes), includePossible: includePossible),
                terminator: ""
            )
        }

        /// Walk up from `directory` to `Package.swift`, then the conventional
        /// index path beneath it. `nil` when no package root or no index.
        private static func resolveIndexPath(startingFrom directory: URL) -> URL? {
            let fileSystem = DefaultFileSystemReader()
            var current = directory.standardizedFileURL
            while true {
                let manifest = current.appendingPathComponent("Package.swift")
                if fileSystem.fileExists(atPath: manifest.path) {
                    let path = current.appendingPathComponent(IndexStore.conventionalRelativePath)
                    return fileSystem.fileExists(atPath: path.path) ? path : nil
                }
                let parent = current.deletingLastPathComponent().standardizedFileURL
                if parent == current { return nil }
                current = parent
            }
        }
    }
}
