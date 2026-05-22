import ArgumentParser
import Foundation
import SwiftInferCore

/// V1.33.D — `swift-infer query` subcommand (PRD §20.1). Reads
/// `.swiftinfer/index.json` and applies basic filters from CLI flags,
/// rendering matching entries to stdout sorted by score descending.
///
/// **No natural-language query DSL in v1.33.** PRD §20.1 sketches
/// `swift-infer query 'monoids in MyApp'`; v1.33 ships structured
/// flag-based filters. A natural-language parser is a future cycle,
/// informed by field experience with what structured queries matter.
///
/// **Flag combinations AND together.** All non-default flags must
/// match for an entry to be returned.

/// Pure-function result of `SwiftInferCommand.Query.runQuery`. At
/// file scope (rather than nested under `Query`) to keep the type
/// hierarchy within SwiftLint's `nesting` rule.
public struct QueryOutcome: Equatable {
    public let rendered: String
    public let warnings: [String]
    public let matchedCount: Int
}

/// Bundle for `Query.applyFilters`'s six filter params, keeping the
/// function under the `function_parameter_count` cap. Each field is
/// optional with the same "nil means don't filter" semantics as the
/// original parameters.
public struct QueryFilters: Equatable {
    public let template: String?
    public let type: String?
    public let tier: String?
    public let decision: String?
    public let minScore: Int?

    public init(
        template: String? = nil,
        type: String? = nil,
        tier: String? = nil,
        decision: String? = nil,
        minScore: Int? = nil
    ) {
        self.template = template
        self.type = type
        self.tier = tier
        self.decision = decision
        self.minScore = minScore
    }
}

extension SwiftInferCommand {

    public struct Query: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "query",
            abstract: "Query the SemanticIndex at `.swiftinfer/index.json` "
                + "(PRD §20.1). Filter by template, type, tier, decision, "
                + "or score; sorted by score descending."
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
            help: "Filter by template name (e.g. 'round-trip', 'idempotence')."
        )
        public var template: String?

        @Option(
            name: .long,
            help: "Filter by carrier type name. Pass 'none' to match free functions (typeName == nil)."
        )
        public var type: String?

        @Option(
            name: .long,
            help: "Filter by tier: Strong, Likely, Possible, Suppressed, or Advisory."
        )
        public var tier: String?

        @Option(
            name: .long,
            help: """
            Filter by recorded decision: accepted, rejected, skipped, \
            acceptedAsConformance, or 'untriaged' (no decision yet).
            """
        )
        public var decision: String?

        @Option(
            name: .long,
            help: "Filter by score lower bound (inclusive). Entries with score < N are excluded."
        )
        public var minScore: Int?

        @Option(
            name: .long,
            help: "Cap output to the first N entries (after score-descending sort)."
        )
        public var limit: Int?

        public init() {}

        public func run() async {
            let result = Self.runQuery(
                directoryOverride: directory,
                explicitIndexPath: indexPath,
                filters: QueryFilters(
                    template: template,
                    type: type,
                    tier: tier,
                    decision: decision,
                    minScore: minScore
                ),
                limit: limit
            )
            for warning in result.warnings {
                FileHandle.standardError.write(
                    Data("warning: \(warning)\n".utf8)
                )
            }
            print(result.rendered, terminator: "")
        }

        /// Pure-function surface so unit tests can drive the query
        /// path without the AsyncParsableCommand shell. V1.89 lint pass —
        /// the original 6 filter params were bundled into `QueryFilters`
        /// (which the function already constructed internally), dropping
        /// the param count from 8 → 4 and eliminating the
        /// `function_parameter_count` disable.
        static func runQuery(
            directoryOverride: String?,
            explicitIndexPath: String?,
            filters: QueryFilters,
            limit: Int?
        ) -> QueryOutcome {
            let directory = URL(fileURLWithPath: directoryOverride ?? ".")
            let explicitPath = explicitIndexPath.map { URL(fileURLWithPath: $0) }
            let now = SwiftInferCommand.Index.isoTimestamp(from: Date())
            let resolvedPath = explicitPath ?? Self.resolveIndexPath(startingFrom: directory)
            guard let resolvedPath else {
                return QueryOutcome(
                    rendered: "No .swiftinfer/index.json found. Run `swift-infer index --target <X>` to build one.\n",
                    warnings: [],
                    matchedCount: 0
                )
            }
            let load = IndexStore.load(from: resolvedPath, nowTimestamp: now)
            let filtered = applyFilters(load.index.entries, filters: filters)
            let sorted = filtered.sorted { $0.score > $1.score }
            let capped: [SemanticIndexEntry]
            if let limit, limit >= 0, limit < sorted.count {
                capped = Array(sorted.prefix(limit))
            } else {
                capped = sorted
            }
            let rendered = renderEntries(capped, totalMatched: filtered.count)
            return QueryOutcome(rendered: rendered, warnings: load.warnings, matchedCount: filtered.count)
        }

        // MARK: - Filtering

        /// Module-internal for V1.33.D unit tests. Per-criterion gates
        /// are split into pure helpers to keep the predicate within
        /// SwiftLint's `cyclomatic_complexity` cap.
        static func applyFilters(
            _ entries: [SemanticIndexEntry],
            filters: QueryFilters
        ) -> [SemanticIndexEntry] {
            entries.filter { entry in
                guard matchesTemplate(entry, filter: filters.template) else { return false }
                guard matchesType(entry, filter: filters.type) else { return false }
                guard matchesTier(entry, filter: filters.tier) else { return false }
                guard matchesDecision(entry, filter: filters.decision) else { return false }
                guard matchesMinScore(entry, threshold: filters.minScore) else { return false }
                return true
            }
        }

        private static func matchesTemplate(_ entry: SemanticIndexEntry, filter: String?) -> Bool {
            guard let filter else { return true }
            return entry.templateName == filter
        }

        private static func matchesType(_ entry: SemanticIndexEntry, filter: String?) -> Bool {
            guard let filter else { return true }
            if filter == "none" { return entry.typeName == nil }
            return entry.typeName == filter
        }

        private static func matchesTier(_ entry: SemanticIndexEntry, filter: String?) -> Bool {
            guard let filter else { return true }
            return entry.tier == filter
        }

        private static func matchesDecision(_ entry: SemanticIndexEntry, filter: String?) -> Bool {
            guard let filter else { return true }
            if filter == "untriaged" { return entry.decision == nil }
            return entry.decision == filter
        }

        private static func matchesMinScore(_ entry: SemanticIndexEntry, threshold: Int?) -> Bool {
            guard let threshold else { return true }
            return entry.score >= threshold
        }

        // MARK: - Rendering

        /// Module-internal for V1.33.D unit tests.
        static func renderEntries(
            _ entries: [SemanticIndexEntry],
            totalMatched: Int
        ) -> String {
            if entries.isEmpty {
                return "No entries match.\n"
            }
            var lines: [String] = []
            lines.append("\(totalMatched) entr\(totalMatched == 1 ? "y" : "ies") matched.")
            lines.append("")
            for entry in entries {
                let typeDisplay = entry.typeName ?? "(none)"
                let decisionDisplay = entry.decision ?? "untriaged"
                lines.append(
                    "[\(entry.tier) \(entry.score)] "
                        + "\(entry.templateName) | \(typeDisplay) | "
                        + "\(entry.primaryFunctionName) — \(entry.location)"
                )
                lines.append(
                    "  decision: \(decisionDisplay)"
                        + (entry.decisionAt.map { " (\($0))" } ?? "")
                        + ", first seen: \(entry.firstSeenAt), last seen: \(entry.lastSeenAt)"
                        + ", identity: \(entry.identityHash)"
                )
            }
            return lines.joined(separator: "\n") + "\n"
        }

        // MARK: - Path resolution

        /// Walk up from `directory` to find `Package.swift`, then read
        /// `<package-root>/.swiftinfer/index.json`. Returns `nil` when
        /// no package root is found OR the index file doesn't exist
        /// (caller emits a guidance message instead of a warning —
        /// "run `swift-infer index` first").
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
