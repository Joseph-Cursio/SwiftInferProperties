import ArgumentParser
import Foundation
import SwiftInferCore

/// V1.102 (cycle-99 calibration helper) — aggregate
/// `.swiftinfer/interaction-decisions.json` files (one per corpus)
/// into a per-family acceptance-rate report suitable for the
/// cycle-N findings doc.
///
/// Two modes mirror v1's `metrics`:
/// - **Default** (no args): walk up from `directory` (or CWD) to
///   `Package.swift`, read `<root>/.swiftinfer/interaction-decisions.json`.
/// - **Aggregation** (≥ 1 `--decisions <path>`): read each file,
///   merge via `InteractionDecisions.merge(_:)`, render.
///
/// Output formats (`--format markdown|plain`, default markdown):
/// - `markdown` — pipe-delimited table for direct paste into
///   `docs/calibration-cycle-N-findings.md`.
/// - `plain` — fixed-width columns for terminal reading.

/// Module-level (not nested in `MetricsInteraction`) per SwiftLint's
/// type-nesting cap. Same posture as v1's `MetricsLoadResult`.
struct MetricsInteractionLoaded {
    let decisions: InteractionDecisions
    let sources: [String]
    let warnings: [String]
}

extension SwiftInferCommand {

    public struct MetricsInteraction: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "metrics-interaction",
            abstract: "Aggregate `.swiftinfer/interaction-decisions.json` into per-family acceptance rates (PRD §19)."
        )

        @Option(
            name: .long,
            help: "Override the package root for default-mode walk-up."
        )
        public var directory: String?

        @Option(
            name: .long,
            parsing: .upToNextOption,
            help: "Path to a `.swiftinfer/interaction-decisions.json` file. Repeatable; multiple paths are merged."
        )
        public var decisions: [String] = []

        @Option(
            name: .long,
            help: "Output format: markdown (default) | plain."
        )
        public var format: String = "markdown"

        public init() { /* no-op */ }

        public func run() async throws {
            let parsedFormat = try Self.parseFormat(format)
            let loaded = Self.loadDecisions(directoryOverride: directory, explicitPaths: decisions)
            let report = InteractionDecisionsAggregator.aggregate(loaded.decisions)
            let rendered = InteractionMetricsRenderer.render(
                report,
                sources: loaded.sources,
                format: parsedFormat
            )
            for warning in loaded.warnings {
                FileHandle.standardError.write(Data((warning + "\n").utf8))
            }
            print(rendered)
        }

        // MARK: - Loading

        /// Dispatches between default walk-up and explicit-path aggregation
        /// on whether any `--decisions` path was supplied. Exposed (non-private
        /// static) for direct testing, mirroring v1's `Metrics.loadAggregate`.
        static func loadDecisions(
            directoryOverride: String?,
            explicitPaths: [String]
        ) -> MetricsInteractionLoaded {
            if explicitPaths.isEmpty {
                return loadDefault(directoryOverride: directoryOverride)
            }
            return loadAggregation(explicitPaths: explicitPaths)
        }

        private static func loadDefault(directoryOverride: String?) -> MetricsInteractionLoaded {
            let directoryURL: URL
            if let directoryOverride {
                directoryURL = URL(fileURLWithPath: directoryOverride).standardizedFileURL
            } else {
                directoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .standardizedFileURL
            }
            let result = InteractionDecisionsLoader.load(startingFrom: directoryURL)
            let sourceLabel = result.packageRoot.map(\.path) ?? "(no package root)"
            return MetricsInteractionLoaded(
                decisions: result.decisions,
                sources: [sourceLabel],
                warnings: result.warnings
            )
        }

        private static func loadAggregation(explicitPaths: [String]) -> MetricsInteractionLoaded {
            var aggregate = InteractionDecisions.empty
            var sources: [String] = []
            var warnings: [String] = []
            for path in explicitPaths {
                let pathURL = URL(fileURLWithPath: path).standardizedFileURL
                let result = InteractionDecisionsLoader.load(
                    startingFrom: pathURL.deletingLastPathComponent(),
                    explicitPath: pathURL
                )
                aggregate = aggregate.merge(result.decisions)
                sources.append(pathURL.path)
                warnings.append(contentsOf: result.warnings)
            }
            return MetricsInteractionLoaded(
                decisions: aggregate,
                sources: sources,
                warnings: warnings
            )
        }

        static func parseFormat(_ raw: String) throws -> InteractionMetricsRenderer.Format {
            guard let parsed = InteractionMetricsRenderer.Format(rawValue: raw.lowercased()) else {
                throw ValidationError(
                    "unknown --format value '\(raw)'. Allowed: "
                        + InteractionMetricsRenderer.Format.allCases
                            .map(\.rawValue).joined(separator: ", ")
                )
            }
            return parsed
        }
    }
}
