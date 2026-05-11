import ArgumentParser
import Foundation
import SwiftInferCore

/// V1.33.C — `swift-infer index` subcommand (PRD §20.1). Builds (or
/// updates) `.swiftinfer/index.json` from a fresh discover pass joined
/// with the existing `.swiftinfer/decisions.json` record.
///
/// **No incremental analysis in v1.33.** The index rebuilds from a full
/// discover each run. PRD §20.1 mentions incremental as a future
/// optimization; deferred until profiling shows it's needed.
extension SwiftInferCommand {

    public struct Index: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "index",
            abstract: "Build or update the SemanticIndex at `.swiftinfer/index.json` "
                + "(PRD §20.1). Joins discover output with the recorded decisions."
        )

        @Option(
            name: .long,
            help: "Name of the SwiftPM target to scan. Resolved to Sources/<target>/ relative to the working directory."
        )
        public var target: String

        @Flag(
            name: .long,
            inversion: .prefixedNo,
            help: """
            Include `Possible` tier suggestions (score 20–39). When \
            building an index, this defaults ON via the Index pipeline \
            (the index is a recall surface; users filter via \
            `swift-infer query --min-score`). Pass --no-include-possible \
            to force Possible-tier suppression.
            """
        )
        public var includePossible: Bool?

        @Option(
            name: .long,
            help: """
            Path to a vocabulary file. When omitted, swift-infer \
            falls back to the path in .swiftinfer/config.toml's \
            [discover].vocabularyPath, then to the conventional \
            .swiftinfer/vocabulary.json next to Package.swift.
            """
        )
        public var vocabulary: String?

        @Option(
            name: .long,
            help: """
            Path to a config file. When omitted, swift-infer walks up \
            from the target directory to the package root and looks for \
            .swiftinfer/config.toml.
            """
        )
        public var config: String?

        @Option(
            name: .long,
            help: """
            Comma-separated list of template packs to enable: \
            numeric, serialization, collections, algebraic, concurrency \
            (PRD §20.3). When omitted, all packs are enabled.
            """
        )
        public var packs: String?

        @Option(
            name: .long,
            help: """
            Path to the directory TestLifter scans for tests. When omitted, \
            swift-infer walks up from the --target directory to find \
            Package.swift, then scans <package-root>/Tests/ if it exists.
            """
        )
        public var testDir: String?

        @Flag(
            name: .long,
            help: """
            Report counts without writing the index. Useful for CI \
            dashboards that summarize "what would the index update do" \
            without mutating the persisted state.
            """
        )
        public var dryRun: Bool = false

        public init() {}

        public func run() async throws {
            let directory = URL(fileURLWithPath: "Sources").appendingPathComponent(target)
            let explicitVocabularyPath = vocabulary.map { URL(fileURLWithPath: $0) }
            let explicitConfigPath = config.map { URL(fileURLWithPath: $0) }
            let explicitTestDirPath = testDir.map { URL(fileURLWithPath: $0) }

            let diagnostics = PrintDiagnosticOutput()
            // Default to includePossible=true for the index — the index
            // is a recall surface and users filter via
            // `swift-infer query --min-score`. Pass --no-include-possible
            // to override (the flag is Bool? per the M2 plan's CLI > config
            // > default precedence; explicit non-nil wins).
            let effectiveIncludePossible = includePossible ?? true
            let pipeline = try Discover.collectVisibleSuggestions(
                directory: directory,
                includePossible: effectiveIncludePossible,
                explicitVocabularyPath: explicitVocabularyPath,
                explicitConfigPath: explicitConfigPath,
                explicitTestDirectory: explicitTestDirPath,
                packsOverride: packs,
                diagnostics: diagnostics
            )
            let packageRoot = pipeline.packageRoot ?? directory

            // Load existing index + decisions (both may be absent on a
            // cold-start run; that's fine — empty values flow through).
            let now = Self.isoTimestampNow()
            let indexPath = IndexStore.defaultPath(for: packageRoot)
            let indexLoad = IndexStore.load(from: indexPath, nowTimestamp: now)
            for warning in indexLoad.warnings {
                diagnostics.writeDiagnostic("warning: \(warning)")
            }
            let decisionsLoad = DecisionsLoader.load(startingFrom: directory)
            for warning in decisionsLoad.warnings {
                diagnostics.writeDiagnostic("warning: \(warning)")
            }
            let decisionsByHash = Dictionary(
                uniqueKeysWithValues: decisionsLoad.decisions.records.map {
                    ($0.identityHash, $0)
                }
            )

            // Project Suggestions → SemanticIndexEntry. The fresh
            // firstSeenAt is `now` for new entries; IndexStore.upsert
            // preserves the prior firstSeenAt for already-known entries.
            let freshEntries = pipeline.suggestions.map { suggestion in
                Self.buildEntry(
                    from: suggestion,
                    decisionsByHash: decisionsByHash,
                    now: now
                )
            }
            let priorCount = indexLoad.index.entries.count
            let priorHashes = Set(indexLoad.index.entries.map(\SemanticIndexEntry.identityHash))
            let freshHashes = Set(freshEntries.map(\SemanticIndexEntry.identityHash))
            let newCount = freshHashes.subtracting(priorHashes).count
            let updatedCount = freshHashes.intersection(priorHashes).count
            let merged = IndexStore.upsert(
                freshEntries,
                into: indexLoad.index,
                at: now
            )
            if dryRun {
                print(
                    "Indexed \(freshEntries.count) suggestion(s) "
                        + "(\(newCount) new, \(updatedCount) updated; "
                        + "prior index had \(priorCount); --dry-run, "
                        + "no write)"
                )
                return
            }
            try IndexStore.save(merged, to: indexPath)
            print(
                "Indexed \(freshEntries.count) suggestion(s) → \(indexPath.path) "
                    + "(\(newCount) new, \(updatedCount) updated; "
                    + "total entries \(merged.entries.count))"
            )
        }

        // MARK: - Suggestion → SemanticIndexEntry projection

        /// Module-internal for V1.33.C unit tests.
        static func buildEntry(
            from suggestion: Suggestion,
            decisionsByHash: [String: DecisionRecord],
            now: String
        ) -> SemanticIndexEntry {
            let evidence = suggestion.evidence.first
            let primaryName = evidence?.displayName ?? "(unknown)"
            let location: String
            if let loc = evidence?.location {
                location = "\(loc.file):\(loc.line)"
            } else {
                location = "(unknown)"
            }
            // SuggestionIdentity.display = "0x<16-char hex>".
            // DecisionRecord.identityHash = "<16-char hex>" (no 0x prefix).
            // Join on the normalized form.
            let displayHash = suggestion.identity.display
            let normalizedHash = suggestion.identity.normalized
            let decisionRecord = decisionsByHash[normalizedHash]
            let decisionString = decisionRecord?.decision.rawValue
            let decisionAt = decisionRecord.map { isoTimestamp(from: $0.timestamp) }
            return SemanticIndexEntry(
                identityHash: displayHash,
                templateName: suggestion.templateName,
                typeName: carrierType(for: suggestion),
                score: suggestion.score.total,
                tier: humanReadableTier(suggestion.score.tier),
                primaryFunctionName: primaryName,
                location: location,
                decision: decisionString,
                decisionAt: decisionAt,
                firstSeenAt: now,
                lastSeenAt: now
            )
        }

        /// Best-effort carrier-type extraction from the evidence
        /// signature. The Evidence struct stores a "trimmed function
        /// signature" string like `"(String) -> String"`; the carrier
        /// type isn't a separate column on Suggestion. v1.33 doesn't
        /// re-parse the signature — returns `nil`, which renders as
        /// "(none)" in query output. v1.34+ can enrich this when the
        /// Suggestion data model widens.
        private static func carrierType(for suggestion: Suggestion) -> String? {
            // Cycle-25/27 evidence shows carrier-aware suggestions
            // (Idempotence-lifted, RoundTrip, InversePair) carry a
            // "Value-semantic carrier (X)" line in whySuggested. v1.33
            // doesn't re-parse that — defer enrichment to v1.34+.
            nil
        }

        private static func humanReadableTier(_ tier: Tier) -> String {
            switch tier {
            case .strong:     return "Strong"
            case .likely:     return "Likely"
            case .possible:   return "Possible"
            case .suppressed: return "Suppressed"
            case .advisory:   return "Advisory"
            }
        }

        private static func isoTimestampNow() -> String {
            isoTimestamp(from: Date())
        }

        static func isoTimestamp(from date: Date) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.string(from: date)
        }
    }
}
