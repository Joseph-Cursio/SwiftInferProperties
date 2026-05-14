import ArgumentParser
import Foundation
import PropertyLawCore
import SwiftInferCore

/// V1.33.C — `swift-infer index` subcommand (PRD §20.1). Builds (or
/// updates) `.swiftinfer/index.json` from a fresh discover pass joined
/// with the existing `.swiftinfer/decisions.json` record.
///
/// **No incremental analysis in v1.33.** The index rebuilds from a full
/// discover each run. PRD §20.1 mentions incremental as a future
/// optimization; deferred until profiling shows it's needed.

/// Diff between a freshly-discovered entry set and the prior on-disk
/// index. At file scope (rather than nested under `Index`) to keep
/// the type hierarchy within SwiftLint's `nesting` rule.
private struct IndexDiff {
    let priorCount: Int
    let newCount: Int
    let updatedCount: Int
}

/// V1.42.C.5 — inputs to `Index.performIndex`. Bundled into one struct
/// (rather than a 7-parameter function) so the static reindex entry
/// point stays under SwiftLint's `function_parameter_count` cap. At
/// file scope, mirroring `IndexDiff`, for the `nesting`-rule reason.
struct IndexInputs {
    /// Discover root: `Sources/<target>` for `swift-infer index`, the
    /// whole `<packageRoot>/Sources` for verify's reindex-on-demand.
    let scanDirectory: URL
    let includePossible: Bool
    let explicitVocabularyPath: URL?
    let explicitConfigPath: URL?
    let explicitTestDirPath: URL?
    let packsOverride: String?
    let dryRun: Bool
}

/// Build the human-readable index-run summary. V1.42.C.5 split this out
/// of the old `reportAndPersist` (which also did the write + `print`):
/// `Index.performIndex` now owns the write and returns this string, so
/// the caller picks the sink (`index` → stdout, `verify` → stderr). At
/// file scope, mirroring `IndexDiff` / `IndexInputs`.
private func indexSummaryLine(
    merged: IndexStore.Index,
    indexPath: URL,
    freshCount: Int,
    diff: IndexDiff,
    dryRun: Bool
) -> String {
    if dryRun {
        return "Indexed \(freshCount) suggestion(s) "
            + "(\(diff.newCount) new, \(diff.updatedCount) updated; "
            + "prior index had \(diff.priorCount); --dry-run, no write)"
    }
    return "Indexed \(freshCount) suggestion(s) → \(indexPath.path) "
        + "(\(diff.newCount) new, \(diff.updatedCount) updated; "
        + "total entries \(merged.entries.count))"
}

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
            // Default to includePossible=true for the index — the index
            // is a recall surface and users filter via
            // `swift-infer query --min-score`. Pass --no-include-possible
            // to override (the flag is Bool? per the M2 plan's CLI > config
            // > default precedence; explicit non-nil wins).
            let (_, summary) = try Self.performIndex(
                IndexInputs(
                    scanDirectory: directory,
                    includePossible: includePossible ?? true,
                    explicitVocabularyPath: vocabulary.map { URL(fileURLWithPath: $0) },
                    explicitConfigPath: config.map { URL(fileURLWithPath: $0) },
                    explicitTestDirPath: testDir.map { URL(fileURLWithPath: $0) },
                    packsOverride: packs,
                    dryRun: dryRun
                ),
                diagnostics: PrintDiagnosticOutput()
            )
            print(summary)
        }

        /// V1.42.C.5 — the discover → project → upsert → save pipeline,
        /// hoisted out of `run()`'s instance method into a callable
        /// static so `swift-infer verify` can drive an implicit reindex
        /// on demand when `.swiftinfer/index.json` is missing or stale.
        /// Returns the merged index plus a human-readable summary line;
        /// the caller decides where the summary goes — `index` prints it
        /// to stdout, `verify` routes it to a stderr diagnostic so it
        /// doesn't pollute the verify outcome / JSON stream.
        static func performIndex(
            _ inputs: IndexInputs,
            diagnostics: any DiagnosticOutput
        ) throws -> (index: IndexStore.Index, summary: String) {
            let pipeline = try Discover.collectVisibleSuggestions(
                directory: inputs.scanDirectory,
                includePossible: inputs.includePossible,
                explicitVocabularyPath: inputs.explicitVocabularyPath,
                explicitConfigPath: inputs.explicitConfigPath,
                explicitTestDirectory: inputs.explicitTestDirPath,
                packsOverride: inputs.packsOverride,
                diagnostics: diagnostics
            )
            let packageRoot = pipeline.packageRoot ?? inputs.scanDirectory
            // Load existing index + decisions (both may be absent on a
            // cold-start run; that's fine — empty values flow through).
            let now = isoTimestampNow()
            let indexPath = IndexStore.defaultPath(for: packageRoot)
            let indexLoad = IndexStore.load(from: indexPath, nowTimestamp: now)
            let decisionsLoad = DecisionsLoader.load(startingFrom: inputs.scanDirectory)
            replayWarnings(indexLoad.warnings + decisionsLoad.warnings, to: diagnostics)
            let decisionsByHash = decisionsByHash(from: decisionsLoad.decisions)
            // Project Suggestions → SemanticIndexEntry. fresh `firstSeenAt`
            // is `now` for new entries; IndexStore.upsert preserves the
            // prior firstSeenAt for already-known entries.
            let freshEntries = pipeline.suggestions.map { suggestion in
                buildEntry(
                    from: suggestion,
                    decisionsByHash: decisionsByHash,
                    typeShapesByName: pipeline.typeShapesByName,
                    now: now
                )
            }
            let diff = computeDiff(priorIndex: indexLoad.index, freshEntries: freshEntries)
            let merged = IndexStore.upsert(freshEntries, into: indexLoad.index, at: now)
            if !inputs.dryRun {
                try IndexStore.save(merged, to: indexPath)
            }
            return (
                merged,
                indexSummaryLine(
                    merged: merged,
                    indexPath: indexPath,
                    freshCount: freshEntries.count,
                    diff: diff,
                    dryRun: inputs.dryRun
                )
            )
        }

        // MARK: - V1.43 cleanup helpers — split out of `run()` to
        // keep the body within SwiftLint's function_body_length cap.

        private static func replayWarnings(
            _ warnings: [String],
            to diagnostics: any DiagnosticOutput
        ) {
            for warning in warnings {
                diagnostics.writeDiagnostic("warning: \(warning)")
            }
        }

        private static func decisionsByHash(from decisions: Decisions) -> [String: DecisionRecord] {
            Dictionary(
                uniqueKeysWithValues: decisions.records.map { ($0.identityHash, $0) }
            )
        }

        private static func computeDiff(
            priorIndex: IndexStore.Index,
            freshEntries: [SemanticIndexEntry]
        ) -> IndexDiff {
            let priorHashes = Set(priorIndex.entries.map(\SemanticIndexEntry.identityHash))
            let freshHashes = Set(freshEntries.map(\SemanticIndexEntry.identityHash))
            return IndexDiff(
                priorCount: priorIndex.entries.count,
                newCount: freshHashes.subtracting(priorHashes).count,
                updatedCount: freshHashes.intersection(priorHashes).count
            )
        }

        // MARK: - Suggestion → SemanticIndexEntry projection

        /// Module-internal for V1.33.C unit tests. V1.47.C adds the
        /// optional `typeShapesByName` parameter — when present, the
        /// projection looks up the carrier's `TypeShape` and mirrors
        /// it onto the entry as `IndexedTypeShape`. Tests that don't
        /// care can pass an empty map.
        static func buildEntry(
            from suggestion: Suggestion,
            decisionsByHash: [String: DecisionRecord],
            typeShapesByName: [String: PropertyLawCore.TypeShape] = [:],
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
            let typeShape = indexedTypeShape(
                for: suggestion,
                typeShapesByName: typeShapesByName
            )
            let secondaryFunctionName = secondaryFunctionName(for: suggestion)
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
                lastSeenAt: now,
                typeShape: typeShape,
                secondaryFunctionName: secondaryFunctionName
            )
        }

        /// V1.49.C.2 — read the round-trip inverse-half name from the
        /// Suggestion's evidence array. The round-trip template emits
        /// `evidence = [forward, reverse]`; v1.49 persists the second
        /// half so the verify resolver can use it as a non-curated
        /// fallback. Returns `nil` for non-round-trip templates and
        /// for evidence arrays with fewer than 2 entries.
        private static func secondaryFunctionName(for suggestion: Suggestion) -> String? {
            guard suggestion.templateName == "round-trip" else { return nil }
            guard suggestion.evidence.count >= 2 else { return nil }
            return suggestion.evidence[1].displayName
        }

        /// V1.47.C — look up the carrier's TypeShape by bare name (no
        /// generic argument list) and mirror it onto the entry. Returns
        /// `nil` when the carrier is a free function (no carrier), a
        /// stdlib raw type the indexer doesn't store TypeShapes for,
        /// or a third-party type whose primary declaration isn't in the
        /// indexed source.
        private static func indexedTypeShape(
            for suggestion: Suggestion,
            typeShapesByName: [String: PropertyLawCore.TypeShape]
        ) -> IndexedTypeShape? {
            guard let carrier = suggestion.carrier else { return nil }
            let bareName = bareTypeName(from: carrier)
            guard let kitShape = typeShapesByName[bareName] else { return nil }
            return IndexedTypeShape(from: kitShape)
        }

        /// Strip the generic argument list from a carrier name so the
        /// `TypeShape` lookup hits the bare declaration name. e.g.
        /// `"OrderedSet<Element>"` → `"OrderedSet"`,
        /// `"Complex<Double>"` → `"Complex"`, `"Int"` → `"Int"`.
        static func bareTypeName(from carrier: String) -> String {
            if let openAngle = carrier.firstIndex(of: "<") {
                return String(carrier[..<openAngle])
            }
            return carrier
        }

        /// V1.34.C — carrier-type extraction. v1.33 deferred this by
        /// returning nil (no `--type` query support). v1.34.A widened
        /// the `Suggestion` data model with `carrier: String?`, and
        /// v1.34.B threaded it through every template's suggest()
        /// emitter + post-template rebuilder + TestLifter promotion.
        /// v1.34.C reads it directly here. `nil` flows through to the
        /// emitted `SemanticIndexEntry.typeName`, which renders as
        /// `(none)` in `query` output and matches `query --type none`.
        private static func carrierType(for suggestion: Suggestion) -> String? {
            suggestion.carrier
        }

        private static func humanReadableTier(_ tier: Tier) -> String {
            switch tier {
            case .verified:   return "Verified"
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
