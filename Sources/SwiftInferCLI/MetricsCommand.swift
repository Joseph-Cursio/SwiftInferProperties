import ArgumentParser
import Foundation
import SwiftInferCore

/// Result of loading a `swift-infer metrics` aggregate from disk —
/// the rolled-up `Decisions`, the `sources` labels for the rendered
/// header, and the `warnings` to surface on stderr. Module-level
/// (rather than nested in `Metrics`) per SwiftLint's nesting rule.
struct MetricsLoadResult: Equatable {
    let decisions: Decisions
    let sources: [String]
    let warnings: [String]
}

/// `swift-infer metrics` — V1.4.1 (closes PRD §17.2's deferred
/// subcommand).
///
/// Reads one or more `.swiftinfer/decisions.json` files, aggregates
/// per-template acceptance / rejection / suppression rates + tier-
/// mix acceptance, and renders a tabular report to stdout. Three of
/// PRD §17.2's five metrics are shippable from the existing
/// `DecisionRecord` shape; the missing two (time-to-adoption + post-
/// acceptance failure rate) require new fields and ship in v1.5+.
///
/// **Default-mode behavior (no args):** walk up from the current
/// directory looking for `Package.swift`, then read
/// `<package-root>/.swiftinfer/decisions.json` (mirrors `discover` /
/// `drift`'s walk-up posture). Single-corpus use case.
///
/// **Aggregation mode (one or more `--decisions <path>` flags):**
/// read each file, fold into one in-memory aggregate via
/// `Decisions.merge(_:)`, render. Calibration use case (V1.4.2 runs
/// across four benchmark corpora).
extension SwiftInferCommand {

    public struct Metrics: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "metrics",
            abstract: "Aggregate `.swiftinfer/decisions.json` into "
                + "acceptance / rejection / suppression rates (PRD §17.2)."
        )

        @Option(
            name: .long,
            help: "Override the package root for default-mode walk-up."
        )
        public var directory: String?

        @Option(
            name: .long,
            parsing: .upToNextOption,
            help: "Path to a `.swiftinfer/decisions.json` file. Repeatable; multiple paths are merged."
        )
        public var decisions: [String] = []

        public init() {}

        public func run() async throws {
            let aggregate = try Self.loadAggregate(
                directoryOverride: directory,
                explicitPaths: decisions
            )
            for warning in aggregate.warnings {
                FileHandle.standardError.write(
                    Data("warning: \(warning)\n".utf8)
                )
            }
            let rendered = MetricsRenderer.render(
                decisions: aggregate.decisions,
                sources: aggregate.sources
            )
            print(rendered, terminator: "")
        }

        /// Pure-function aggregation surface so unit tests can drive
        /// the loader path without the AsyncParsableCommand shell.
        static func loadAggregate(
            directoryOverride: String?,
            explicitPaths: [String]
        ) throws -> MetricsLoadResult {
            if !explicitPaths.isEmpty {
                return loadExplicitPaths(explicitPaths)
            }
            return loadImplicit(directoryOverride: directoryOverride)
        }

        // MARK: - Explicit `--decisions <path>` mode

        private static func loadExplicitPaths(_ paths: [String]) -> MetricsLoadResult {
            var aggregate = Decisions.empty
            var sources: [String] = []
            var warnings: [String] = []
            for raw in paths {
                let url = URL(fileURLWithPath: raw)
                let result = DecisionsLoader.load(
                    startingFrom: url.deletingLastPathComponent(),
                    explicitPath: url
                )
                warnings.append(contentsOf: result.warnings)
                aggregate = aggregate.merge(result.decisions)
                sources.append(raw)
            }
            return MetricsLoadResult(decisions: aggregate, sources: sources, warnings: warnings)
        }

        // MARK: - Default walk-up mode

        private static func loadImplicit(directoryOverride: String?) -> MetricsLoadResult {
            let startDirectory = startingDirectory(override: directoryOverride)
            let result = DecisionsLoader.load(startingFrom: startDirectory)
            let label: String = {
                if let root = result.packageRoot {
                    return DecisionsLoader.defaultPath(for: root).path
                }
                return startDirectory.path
            }()
            return MetricsLoadResult(
                decisions: result.decisions,
                sources: [label],
                warnings: result.warnings
            )
        }

        private static func startingDirectory(override: String?) -> URL {
            if let override {
                return URL(fileURLWithPath: override)
            }
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }
    }
}
