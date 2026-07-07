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

/// V1.141 — freshly-discovered row counts for the run summary, bundled so
/// `indexSummaryLine` stays within SwiftLint's `function_parameter_count`
/// cap. `algebraic` = `Suggestion` rows, `interaction` = reducer / MVVM
/// invariant rows.
private struct IndexFreshCounts {
    let algebraic: Int
    let interaction: Int
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
    /// V1.141 — the bare `--target` name, present only on the single-target
    /// `index --target` path. `nil` on verify's whole-`Sources` reindex,
    /// where interaction-surface indexing is skipped (the interaction
    /// discoverer takes a target name + working directory, not a raw
    /// directory).
    let targetName: String?
    /// V1.141 — working directory the interaction discoverer resolves
    /// `Sources/<target>` against. `nil` alongside `targetName`.
    let workingDirectory: URL?

    init(
        scanDirectory: URL,
        includePossible: Bool,
        explicitVocabularyPath: URL?,
        explicitConfigPath: URL?,
        explicitTestDirPath: URL?,
        packsOverride: String?,
        dryRun: Bool,
        targetName: String? = nil,
        workingDirectory: URL? = nil
    ) {
        self.scanDirectory = scanDirectory
        self.includePossible = includePossible
        self.explicitVocabularyPath = explicitVocabularyPath
        self.explicitConfigPath = explicitConfigPath
        self.explicitTestDirPath = explicitTestDirPath
        self.packsOverride = packsOverride
        self.dryRun = dryRun
        self.targetName = targetName
        self.workingDirectory = workingDirectory
    }
}

/// Build the human-readable index-run summary. V1.42.C.5 split this out
/// of the old `reportAndPersist` (which also did the write + `print`):
/// `Index.performIndex` now owns the write and returns this string, so
/// the caller picks the sink (`index` → stdout, `verify` → stderr). At
/// file scope, mirroring `IndexDiff` / `IndexInputs`.
private func indexSummaryLine(
    merged: IndexStore.Index,
    indexPath: URL,
    counts: IndexFreshCounts,
    diff: IndexDiff,
    dryRun: Bool
) -> String {
    let interactionClause = counts.interaction > 0
        ? " + \(counts.interaction) interaction invariant(s)"
        : ""
    if dryRun {
        return "Indexed \(counts.algebraic) suggestion(s)\(interactionClause) "
            + "(\(diff.newCount) new, \(diff.updatedCount) updated; "
            + "prior index had \(diff.priorCount); --dry-run, no write)"
    }
    return "Indexed \(counts.algebraic) suggestion(s)\(interactionClause) → \(indexPath.path) "
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

        public init() { /* no-op */ }

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
                    dryRun: dryRun,
                    // V1.141 — enable interaction-surface indexing: the
                    // interaction discoverer resolves Sources/<target> against
                    // the working directory (matching `directory`'s relative
                    // `Sources/<target>` for the algebraic scan).
                    targetName: target,
                    workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
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
            // WS-6 Slice 2 — persist the whole-module shape universe (not just
            // per-entry carrier shapes) so verify can build a `GeneratorResolver`
            // over every scanned type and recursively derive nested custom-type
            // carriers. Mirror each kit `TypeShape` to its `IndexedTypeShape`.
            let freshShapes = pipeline.typeShapesByName.mapValues { IndexedTypeShape(from: $0) }
            let diff = computeDiff(priorIndex: indexLoad.index, freshEntries: freshEntries)
            var merged = IndexStore.upsert(
                freshEntries,
                into: indexLoad.index,
                at: now,
                typeShapes: freshShapes
            )
            // V1.141 — also index the interaction surface (reducer / MVVM
            // invariant families) on the single-target `index --target` path.
            // No-op on verify's whole-Sources reindex (no targetName).
            let freshInteraction = interactionEntries(for: inputs, now: now, diagnostics: diagnostics)
            merged = IndexStore.upsertInteraction(freshInteraction, into: merged, at: now)
            if !inputs.dryRun {
                try IndexStore.save(merged, to: indexPath)
            }
            return (
                merged,
                indexSummaryLine(
                    merged: merged,
                    indexPath: indexPath,
                    counts: IndexFreshCounts(
                        algebraic: freshEntries.count,
                        interaction: freshInteraction.count
                    ),
                    diff: diff,
                    dryRun: inputs.dryRun
                )
            )
        }

        // MARK: - V1.43 cleanup helpers — split out of `run()` to
        // keep the body within SwiftLint's function_body_length cap.

        // Internal (not private): `IndexCommand+Projection`'s
        // `interactionEntries` replays interaction-decision load warnings
        // through this same helper across the file boundary.
        static func replayWarnings(
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
