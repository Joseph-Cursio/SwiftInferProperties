import ArgumentParser
import Foundation
import SwiftInferCore

/// V1.35.B — `swift-infer suggest-refactors` subcommand. Reads
/// `.swiftinfer/index.json`, runs `RefactorClusterAnalyzer.analyze`,
/// and renders human-readable refactor suggestions per cluster.
///
/// Read-only over the SemanticIndex output. Per PRD §16 #1, v1
/// subcommands never modify source — `suggest-refactors` is a render
/// surface.
extension SwiftInferCommand {

    public struct SuggestRefactors: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "suggest-refactors",
            abstract: "Surface carrier-aware refactor suggestions from "
                + "`.swiftinfer/index.json` (PRD §20.1 use case). "
                + "Read-only; never modifies source."
        )

        @Option(
            name: .long,
            help: "Override the package root for default-mode walk-up."
        )
        public var directory: String?

        @Option(
            name: .long,
            help: """
            Path to a specific index file. When omitted, swift-infer \
            walks up from the working directory to find Package.swift, \
            then reads `<package-root>/.swiftinfer/index.json`.
            """
        )
        public var indexPath: String?

        @Option(
            name: .long,
            help: "Filter clusters below this size (default 3)."
        )
        public var minSuggestions: Int = 3

        @Option(
            name: .long,
            help: """
            Filter by cluster shape: algebraicStructure, \
            idempotenceCluster, dualStyleCluster, roundTripCluster, \
            generalCluster.
            """
        )
        public var shape: String?

        @Option(
            name: .long,
            help: "Cap output to the first N clusters."
        )
        public var limit: Int?

        public init() {}

        public func run() async throws {
            let result = try Self.runSuggestRefactors(
                directoryOverride: directory,
                explicitIndexPath: indexPath,
                minSuggestions: minSuggestions,
                shape: shape,
                limit: limit
            )
            for warning in result.warnings {
                FileHandle.standardError.write(
                    Data("warning: \(warning)\n".utf8)
                )
            }
            print(result.rendered, terminator: "")
        }

        public struct Outcome: Equatable {
            public let rendered: String
            public let warnings: [String]
            public let clusterCount: Int
        }

        /// Pure-function surface so unit tests can drive the subcommand
        /// without the AsyncParsableCommand shell.
        static func runSuggestRefactors(
            directoryOverride: String?,
            explicitIndexPath: String?,
            minSuggestions: Int,
            shape: String?,
            limit: Int?
        ) throws -> Outcome {
            let directory = URL(fileURLWithPath: directoryOverride ?? ".")
            let explicitPath = explicitIndexPath.map { URL(fileURLWithPath: $0) }
            let now = SwiftInferCommand.Index.isoTimestamp(from: Date())
            let resolvedPath = explicitPath ?? Self.resolveIndexPath(startingFrom: directory)
            guard let resolvedPath else {
                return Outcome(
                    rendered: "No .swiftinfer/index.json found. Run `swift-infer index --target <X>` to build one.\n",
                    warnings: [],
                    clusterCount: 0
                )
            }
            let load = IndexStore.load(from: resolvedPath, nowTimestamp: now)
            let allClusters = RefactorClusterAnalyzer.analyze(load.index.entries)
            let filtered = applyFilters(
                allClusters,
                minSuggestions: minSuggestions,
                shape: shape
            )
            let capped: [RefactorCluster]
            if let limit, limit >= 0, limit < filtered.count {
                capped = Array(filtered.prefix(limit))
            } else {
                capped = filtered
            }
            let rendered = renderClusters(capped, totalMatched: filtered.count)
            return Outcome(rendered: rendered, warnings: load.warnings, clusterCount: filtered.count)
        }

        // MARK: - Filtering

        /// Module-internal for V1.35.B unit tests.
        static func applyFilters(
            _ clusters: [RefactorCluster],
            minSuggestions: Int,
            shape: String?
        ) -> [RefactorCluster] {
            clusters.filter { cluster in
                if cluster.totalSuggestionCount < minSuggestions { return false }
                if let shape, cluster.shape.rawValue != shape { return false }
                return true
            }
        }

        // MARK: - Rendering

        /// Module-internal for V1.35.B unit tests.
        static func renderClusters(
            _ clusters: [RefactorCluster],
            totalMatched: Int
        ) -> String {
            if clusters.isEmpty {
                return "No refactor clusters match.\n"
            }
            var lines: [String] = []
            lines.append("\(totalMatched) refactor cluster\(totalMatched == 1 ? "" : "s") found.")
            lines.append("")
            for cluster in clusters {
                lines.append(
                    "[\(cluster.typeName)] \(cluster.totalSuggestionCount) "
                        + "inferred propert\(cluster.totalSuggestionCount == 1 ? "y" : "ies") "
                        + "— \(humanReadableShape(cluster.shape))"
                )
                lines.append("  templates: \(formatTemplateCounts(cluster.perTemplateCounts))")
                lines.append("  representatives: \(cluster.representativeFunctions.joined(separator: ", "))")
                lines.append("  suggestion: \(suggestionText(for: cluster.shape))")
                lines.append("")
            }
            return lines.joined(separator: "\n")
        }

        /// Module-internal for V1.35.B unit tests verifying stable
        /// curated text per shape (so users can grep for it in PR
        /// descriptions).
        static func suggestionText(for shape: ClusterShape) -> String {
            switch shape {
            case .algebraicStructure:
                return """
                This type has multiple commutativity/associativity/identity-element \
                suggestions. If your kit publishes Semigroup / Monoid / \
                CommutativeMonoid / Semilattice, formal conformance lets \
                SwiftPropertyLaws verify the laws on every CI run.
                """
            case .idempotenceCluster:
                return """
                This type has several idempotent operations. If they're \
                CoW-stable mutators (`var c = a; c.op(); c.op()` produces the same \
                state as one call), consider documenting the idempotence invariant \
                on the type's API contract. A shared "IdempotentNormalize"-style \
                protocol may capture the pattern across multiple such types.
                """
            case .dualStyleCluster:
                return """
                This type has several form/non-form mutating-pair APIs. The pattern \
                suggests a SetAlgebra-shape abstraction; formal SetAlgebra \
                conformance (or a custom protocol) lets the kit verify the \
                paired-mutation laws on every CI run.
                """
            case .roundTripCluster:
                return """
                This type has several round-trip pairs. The pattern suggests a \
                codec / serialization-bearing structure; consider extracting a \
                Codec-shaped protocol that captures the (encode, decode) pair \
                explicitly.
                """
            case .generalCluster:
                return """
                This type has many inferred properties across mixed templates. \
                Worth a focused review to see whether the cluster reveals a \
                latent protocol or whether the suggestions span unrelated \
                aspects of the type.
                """
            }
        }

        private static func humanReadableShape(_ shape: ClusterShape) -> String {
            switch shape {
            case .algebraicStructure:  return "algebraic-structure cluster"
            case .idempotenceCluster:  return "idempotence cluster"
            case .dualStyleCluster:    return "dual-style-consistency cluster"
            case .roundTripCluster:    return "round-trip cluster"
            case .generalCluster:      return "general cluster"
            }
        }

        /// Format `[String: Int]` as a stable `"name1 ×N1, name2 ×N2"`
        /// string. Sort by count descending, then by name ascending for
        /// stability across runs.
        private static func formatTemplateCounts(_ counts: [String: Int]) -> String {
            counts
                .sorted { lhs, rhs in
                    if lhs.value != rhs.value { return lhs.value > rhs.value }
                    return lhs.key < rhs.key
                }
                .map { "\($0.key) ×\($0.value)" }
                .joined(separator: ", ")
        }

        // MARK: - Path resolution

        /// Walk up from `directory` to find `Package.swift`, then read
        /// `<package-root>/.swiftinfer/index.json`. Returns `nil` when
        /// no package root is found OR the index file doesn't exist.
        private static func resolveIndexPath(startingFrom directory: URL) -> URL? {
            let fileSystem = DefaultFileSystemReader()
            var current = directory.standardizedFileURL
            while true {
                let manifest = current.appendingPathComponent("Package.swift")
                if fileSystem.fileExists(atPath: manifest.path) {
                    let path = current.appendingPathComponent(IndexStore.conventionalRelativePath)
                    if fileSystem.fileExists(atPath: path.path) {
                        return path
                    }
                    return nil
                }
                let parent = current.deletingLastPathComponent().standardizedFileURL
                if parent == current { return nil }
                current = parent
            }
        }
    }
}
