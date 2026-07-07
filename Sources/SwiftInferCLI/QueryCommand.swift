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

/// Bundle for `Query.applyFilters`'s filter params, keeping the function
/// under the `function_parameter_count` cap. Each field is optional with
/// the same "nil means don't filter" semantics as the original
/// parameters.
public struct QueryFilters: Equatable {
    public let template: String?
    public let type: String?
    public let tier: String?
    public let decision: String?
    public let minScore: Int?
    /// V1.141 — interaction-only: filter by invariant family rawValue
    /// (e.g. `idempotence`, `referential-integrity`). Setting it excludes
    /// algebraic rows (they have no family).
    public let family: String?
    /// V1.141 — which surface(s) to return. Default `.all`.
    public let surface: QuerySurface

    public init(
        template: String? = nil,
        type: String? = nil,
        tier: String? = nil,
        decision: String? = nil,
        minScore: Int? = nil,
        family: String? = nil,
        surface: QuerySurface = .all
    ) {
        self.template = template
        self.type = type
        self.tier = tier
        self.decision = decision
        self.minScore = minScore
        self.family = family
        self.surface = surface
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
            help: """
            Interaction-only: filter by invariant family (e.g. 'idempotence', \
            'referential-integrity', 'cardinality', 'biconditional', \
            'conservation'). Setting it excludes algebraic rows.
            """
        )
        public var family: String?

        @Option(
            name: .long,
            help: """
            Which index surface to query: algebraic (pure-function laws), \
            interaction (reducer / MVVM invariants), or all (default).
            """
        )
        public var surface: String?

        @Option(
            name: .long,
            help: "Cap output to the first N entries (after score-descending sort)."
        )
        public var limit: Int?

        public init() { /* no-op */ }

        public func run() async {
            let (parsedSurface, surfaceWarning) = QuerySurface.parse(surface)
            let result = Self.runQuery(
                directoryOverride: directory,
                explicitIndexPath: indexPath,
                filters: QueryFilters(
                    template: template,
                    type: type,
                    tier: tier,
                    decision: decision,
                    minScore: minScore,
                    family: family,
                    surface: parsedSurface
                ),
                limit: limit
            )
            var warnings = result.warnings
            if let surfaceWarning { warnings.insert(surfaceWarning, at: 0) }
            for warning in warnings {
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

            // Algebraic surface: included when --surface allows it AND no
            // interaction-only filter (--family) is active (algebraic rows
            // have no family, so they could never match one).
            let algebraicMatched = (filters.surface.includesAlgebraic && filters.family == nil)
                ? applyFilters(load.index.entries, filters: filters).sorted { $0.score > $1.score }
                : []
            // Interaction surface: included when --surface allows it AND no
            // algebraic-only filter (--template / --type) is active.
            let algebraicOnlyFilter = filters.template != nil || filters.type != nil
            let interactionMatched = (filters.surface.includesInteraction && !algebraicOnlyFilter)
                ? applyInteractionFilters(load.index.interactionEntries, filters: filters)
                    .sorted { $0.score > $1.score }
                : []

            let totalMatched = algebraicMatched.count + interactionMatched.count
            // Limit caps the combined output: algebraic rows first, then
            // interaction rows fill any remainder.
            let cappedAlgebraic = capped(algebraicMatched, to: limit)
            let interactionLimit = limit.map { max(0, $0 - cappedAlgebraic.count) }
            let cappedInteraction = capped(interactionMatched, to: interactionLimit)

            let rendered = renderCombined(
                algebraic: cappedAlgebraic,
                interaction: cappedInteraction,
                totalMatched: totalMatched
            )
            return QueryOutcome(rendered: rendered, warnings: load.warnings, matchedCount: totalMatched)
        }

        private static func capped<Element>(_ items: [Element], to limit: Int?) -> [Element] {
            guard let limit, limit >= 0, limit < items.count else { return items }
            return Array(items.prefix(limit))
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

        /// Module-internal for V1.33.D unit tests. The algebraic-only
        /// renderer (unchanged output); `runQuery` uses `renderCombined`.
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
            for entry in entries { lines += algebraicEntryLines(entry) }
            return lines.joined(separator: "\n") + "\n"
        }

        /// V1.141 — render both surfaces under one match header. Algebraic
        /// rows first, then (if any) an "Interaction invariants:" section.
        static func renderCombined(
            algebraic: [SemanticIndexEntry],
            interaction: [InteractionIndexEntry],
            totalMatched: Int
        ) -> String {
            if algebraic.isEmpty, interaction.isEmpty {
                return "No entries match.\n"
            }
            var lines: [String] = []
            lines.append("\(totalMatched) entr\(totalMatched == 1 ? "y" : "ies") matched.")
            lines.append("")
            for entry in algebraic { lines += algebraicEntryLines(entry) }
            if !interaction.isEmpty {
                if !algebraic.isEmpty { lines.append("") }
                lines.append("Interaction invariants:")
                for entry in interaction { lines += interactionEntryLines(entry) }
            }
            return lines.joined(separator: "\n") + "\n"
        }

        private static func algebraicEntryLines(_ entry: SemanticIndexEntry) -> [String] {
            let typeDisplay = entry.typeName ?? "(none)"
            let decisionDisplay = entry.decision ?? "untriaged"
            return [
                "[\(entry.tier) \(entry.score)] "
                    + "\(entry.templateName) | \(typeDisplay) | "
                    + "\(entry.primaryFunctionName) — \(entry.location)",
                "  decision: \(decisionDisplay)"
                    + (entry.decisionAt.map { " (\($0))" } ?? "")
                    + ", first seen: \(entry.firstSeenAt), last seen: \(entry.lastSeenAt)"
                    + ", identity: \(entry.identityHash)"
            ]
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
