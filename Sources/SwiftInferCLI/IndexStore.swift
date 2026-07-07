import Foundation
import SwiftInferCore

/// V1.33.B — JSON-backed persistence for the SemanticIndex
/// (PRD §20.1). Mirrors the `DecisionsLoader` shape (load /
/// `Result`-bundled warnings / explicit-vs-implicit-path resolution +
/// write/atomic) so the two store layers stay consistent.
///
/// **Schema versioning.** Every persisted index carries an explicit
/// `schemaVersion: Int = 1` from v1.33. Future versions detect older
/// values and migrate; the v1 format is forward-stable.
///
/// **Why JSON not SQLite.** PRD §20.1 sketches SQLite. v1.33 ships
/// JSON because the storage format is implementation detail and JSON
/// keeps scope contained (no new dependency, no schema-migration
/// design upfront). SQLite is a non-breaking format-swap for a future
/// cycle when query complexity warrants it.
public enum IndexStore {

    /// Conventional path beneath `<package-root>/.swiftinfer/`.
    public static let conventionalRelativePath = ".swiftinfer/index.json"

    /// Current schema version. Increment on backward-incompatible
    /// schema changes; pre-existing v1 files implicitly map to 1 when
    /// the field is absent.
    ///
    /// **History.** v1 = v1.33 initial format. v2 = v1.47 — adds the
    /// optional `typeShape: IndexedTypeShape?` field on
    /// `SemanticIndexEntry`. v3 = v1.49 — adds the optional
    /// `secondaryFunctionName: String?` field on `SemanticIndexEntry`
    /// for non-curated round-trip pair derivation. v4 = WS-6 — adds the
    /// optional `typeShapes: [String: IndexedTypeShape]` map on the `Index`
    /// root (the whole-module shape universe for recursive verify-time
    /// derivation). v5 = V1.141 — adds the optional `interactionEntries:
    /// [InteractionIndexEntry]` array on the `Index` root (the
    /// interaction-surface index rows: reducer / MVVM invariant families).
    /// Every bump is backward-compatible (`decodeIfPresent`), so v1–v4
    /// files decode cleanly into v5 — the version bump on the wrapping
    /// `Index` is informational only.
    public static let currentSchemaVersion: Int = 5

    /// The on-disk index value. Encoded as JSON with stable key
    /// ordering (alphabetical) + pretty-printing so diffs are clean
    /// across runs. Entries are sorted by `identityHash` to make
    /// version-control diffs minimal.
    private enum IndexCodingKeys: String, CodingKey {
        case schemaVersion, updatedAt, entries, typeShapes, interactionEntries
    }

    public struct Index: Codable, Sendable, Equatable {
        public var schemaVersion: Int
        public var updatedAt: String
        public var entries: [SemanticIndexEntry]

        /// WS-6 Slice 2 — the whole-module shape universe, keyed by bare type
        /// name. Lets `verify` build a `GeneratorResolver` over every scanned
        /// type and recursively derive a carrier whose members / init-params are
        /// nested custom types (the per-entry `typeShape` only carries the
        /// carrier's own shape, not its dependencies). Absent in v1–v3 files →
        /// decodes to `[:]` (back-compat), so an un-reindexed project simply
        /// gets no recursion until its next `index` run.
        public var typeShapes: [String: IndexedTypeShape]

        /// V1.141 — the interaction-surface index rows (reducer / MVVM
        /// invariant families). Parallel to `entries` (the algebraic
        /// surface) rather than merged into it, because
        /// `InteractionIndexEntry` and `SemanticIndexEntry` carry disjoint
        /// column sets. Absent in v1–v4 files → decodes to `[]`
        /// (back-compat), so an un-reindexed project simply has no
        /// interaction rows until its next `index` run.
        public var interactionEntries: [InteractionIndexEntry]

        public init(
            schemaVersion: Int = IndexStore.currentSchemaVersion,
            updatedAt: String,
            entries: [SemanticIndexEntry],
            typeShapes: [String: IndexedTypeShape] = [:],
            interactionEntries: [InteractionIndexEntry] = []
        ) {
            self.schemaVersion = schemaVersion
            self.updatedAt = updatedAt
            self.entries = entries
            self.typeShapes = typeShapes
            self.interactionEntries = interactionEntries
        }

        /// Custom decode so v1–v4 files (no `typeShapes` / `interactionEntries`
        /// key) load cleanly. `schemaVersion` / `updatedAt` / `entries` are
        /// always present; `typeShapes` and `interactionEntries` are
        /// optional-with-default. `encode(to:)` stays synthesized.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: IndexCodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            updatedAt = try container.decode(String.self, forKey: .updatedAt)
            entries = try container.decode([SemanticIndexEntry].self, forKey: .entries)
            typeShapes = try container.decodeIfPresent(
                [String: IndexedTypeShape].self, forKey: .typeShapes
            ) ?? [:]
            interactionEntries = try container.decodeIfPresent(
                [InteractionIndexEntry].self, forKey: .interactionEntries
            ) ?? []
        }

        /// Empty index with the current run timestamp.
        public static func empty(at timestamp: String) -> Self {
            Self(updatedAt: timestamp, entries: [])
        }
    }

    /// Result of a `load(...)` call. Mirrors `DecisionsLoader.Result`:
    /// always returns a usable `Index` (`.empty(at:)` when the file is
    /// missing or malformed) plus a warnings array surfaced to stderr
    /// by the caller.
    public struct LoadResult: Equatable {
        public let index: Index
        public let warnings: [String]
        public let path: URL?

        public init(index: Index, warnings: [String], path: URL?) {
            self.index = index
            self.warnings = warnings
            self.path = path
        }
    }

    // MARK: - Load

    public static func load(
        from path: URL,
        nowTimestamp: String,
        fileSystem: FileSystemReader = DefaultFileSystemReader()
    ) -> LoadResult {
        guard fileSystem.fileExists(atPath: path.path) else {
            return LoadResult(
                index: .empty(at: nowTimestamp),
                warnings: [],
                path: path
            )
        }
        do {
            let data = try fileSystem.contents(of: path)
            let decoded = try canonicalDecoder.decode(Index.self, from: data)
            return LoadResult(index: decoded, warnings: [], path: path)
        } catch let error as DecodingError {
            return LoadResult(
                index: .empty(at: nowTimestamp),
                warnings: ["could not decode index at \(path.path): \(error.localizedDescription)"],
                path: path
            )
        } catch {
            return LoadResult(
                index: .empty(at: nowTimestamp),
                warnings: ["could not read index at \(path.path): \(error.localizedDescription)"],
                path: path
            )
        }
    }

    /// Conventional path beneath `packageRoot`.
    public static func defaultPath(for packageRoot: URL) -> URL {
        packageRoot.appendingPathComponent(conventionalRelativePath)
    }

    // MARK: - Save

    /// Write `index` to `path` atomically. Creates the parent directory
    /// chain (`.swiftinfer/`) if needed.
    public static func save(_ index: Index, to path: URL) throws {
        let data = try canonicalEncoder.encode(index)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: path, options: .atomic)
    }

    // MARK: - Upsert

    /// Merge `freshEntries` into `existing` at `runTimestamp`. For each
    /// fresh entry:
    ///   - If `existing.entries` already has a row with the same
    ///     `identityHash`, the row is updated via
    ///     `SemanticIndexEntry.updated(from:)` — preserving
    ///     `firstSeenAt` from the old row while taking the rest from
    ///     `freshEntries`.
    ///   - Otherwise the new entry joins `existing.entries` with
    ///     `firstSeenAt = lastSeenAt = runTimestamp` (the caller has
    ///     already populated those fields in `freshEntries`).
    ///
    /// Entries in `existing` that no longer appear in `freshEntries`
    /// are **kept** — historical entries are valuable for "what
    /// disappeared since last index" queries (v1.34+ feature).
    /// `updatedAt` on the returned `Index` is set to `runTimestamp`.
    ///
    /// Entries are sorted by `identityHash` in the returned index so
    /// the JSON output is stable across runs.
    public static func upsert(
        _ freshEntries: [SemanticIndexEntry],
        into existing: Index,
        at runTimestamp: String,
        typeShapes freshShapes: [String: IndexedTypeShape] = [:]
    ) -> Index {
        var byHash = Dictionary(
            uniqueKeysWithValues: existing.entries.map { ($0.identityHash, $0) }
        )
        for fresh in freshEntries {
            if let existing = byHash[fresh.identityHash] {
                byHash[fresh.identityHash] = existing.updated(from: fresh)
            } else {
                byHash[fresh.identityHash] = fresh
            }
        }
        let merged = byHash.values.sorted { $0.identityHash < $1.identityHash }
        // WS-6 Slice 2 — the current scan is authoritative for shapes it
        // rediscovered; keep any prior shapes it didn't (mirrors the
        // keep-historical-entries policy). Default empty map → shapes unchanged,
        // so existing callers/tests that don't pass shapes lose nothing.
        var mergedShapes = existing.typeShapes
        mergedShapes.merge(freshShapes) { _, fresh in fresh }
        return Index(
            schemaVersion: existing.schemaVersion,
            updatedAt: runTimestamp,
            entries: Array(merged),
            typeShapes: mergedShapes,
            interactionEntries: existing.interactionEntries
        )
    }

    /// V1.141 — merge `freshEntries` (interaction-surface rows) into
    /// `existing.interactionEntries` at `runTimestamp`. Same semantics as
    /// ``upsert(_:into:at:typeShapes:)`` on the algebraic surface: match on
    /// `identityHash`, refresh via `InteractionIndexEntry.updated(from:)`
    /// (preserving `firstSeenAt`), keep historical entries that no longer
    /// appear, and sort by `identityHash` for stable diffs. The algebraic
    /// `entries` / `typeShapes` are carried through unchanged, so this
    /// composes after `upsert` in the same index-build pass.
    public static func upsertInteraction(
        _ freshEntries: [InteractionIndexEntry],
        into existing: Index,
        at runTimestamp: String
    ) -> Index {
        var byHash = Dictionary(
            uniqueKeysWithValues: existing.interactionEntries.map { ($0.identityHash, $0) }
        )
        for fresh in freshEntries {
            if let priorEntry = byHash[fresh.identityHash] {
                byHash[fresh.identityHash] = priorEntry.updated(from: fresh)
            } else {
                byHash[fresh.identityHash] = fresh
            }
        }
        let merged = byHash.values.sorted { $0.identityHash < $1.identityHash }
        return Index(
            schemaVersion: existing.schemaVersion,
            updatedAt: runTimestamp,
            entries: existing.entries,
            typeShapes: existing.typeShapes,
            interactionEntries: Array(merged)
        )
    }

    // MARK: - Encoders

    /// Stable JSON encoder: sorted keys + pretty-printing so the file
    /// diffs cleanly across runs and ISO8601 dates parse on every
    /// platform.
    private static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()

    private static let canonicalDecoder = JSONDecoder()
}
