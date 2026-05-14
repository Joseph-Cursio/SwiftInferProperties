import Foundation
import SwiftInferCore

/// V1.42.C.1 — suggestion-lookup core of the verify pipeline.
///
/// **Scope.** V1.42.C.1 ships hash-prefix lookup against the existing
/// `IndexStore.Index`. The implicit-reindex behavior the v1.42 plan
/// describes ("if `.swiftinfer/index.json` is missing or stale, verify
/// reindexes on demand before the lookup") **landed in V1.42.C.5** —
/// `SwiftInferCommand.Verify.reindexIfNeeded` rebuilds the conventional
/// index from a whole-`Sources/` discover pass before `resolveIndex`
/// runs. `resolveIndex` itself is unchanged: it still throws
/// `.indexMissing` for an explicit `--index-path` that doesn't exist
/// (an explicit path is used as-is, never auto-rebuilt) and still
/// surfaces `staleWarnings` — but in the default-path flow the reindex
/// pre-step means a missing index is rebuilt rather than fatal.
///
/// **Module-internal vs public.** The lookup helpers are module-internal
/// so the upcoming V1.42.C.2/C.3/C.4 sub-steps can compose them without
/// going through the `Verify` subcommand shell. Tests use `@testable
/// import` to drive them directly.
public enum VerifyHarness {

    /// Result of a successful lookup. Carries the resolved entry plus
    /// any diagnostic warnings (e.g. "index appears stale; consider
    /// running `swift-infer index --target <X>` to refresh") so the
    /// caller can surface them on stderr without mutating stdout.
    public struct LookupResult: Equatable {
        public let entry: SemanticIndexEntry
        public let warnings: [String]

        public init(entry: SemanticIndexEntry, warnings: [String]) {
            self.entry = entry
            self.warnings = warnings
        }
    }

    /// Result of `resolveIndex(...)`. A 3-field struct rather than a
    /// tuple — the `large_tuple` lint rule caps at 2 members.
    public struct ResolvedIndex: Equatable {
        public let index: IndexStore.Index
        public let path: URL
        public let warnings: [String]

        public init(index: IndexStore.Index, path: URL, warnings: [String]) {
            self.index = index
            self.path = path
            self.warnings = warnings
        }
    }

    /// Look up exactly one `SemanticIndexEntry` whose `identityHash`
    /// starts with `hashPrefix`. The match is case-insensitive and
    /// tolerates / strips a leading `0x` on the prefix (so the user
    /// can copy either `"0xBC43"` or `"BC43"` from a discover block).
    ///
    /// **Failure modes:**
    ///   - **No entry matches** → `.suggestionNotFound(prefix:closest:)`
    ///     names the prefix and the 3 lexically-closest hashes so the
    ///     user sees what was nearby.
    ///   - **Multiple entries match** → `.ambiguousPrefix(prefix:matches:)`
    ///     names the matched hashes (up to 5).
    ///   - **Index has zero entries** → `.indexEmpty(path:)`
    ///     instructs the user to run `swift-infer index --target <X>`.
    ///
    /// **Index staleness** is the caller's responsibility — pass
    /// `staleWarnings` through from `resolveIndex(...)`.
    static func lookupSuggestion(
        hashPrefix rawPrefix: String,
        in index: IndexStore.Index,
        staleWarnings: [String] = [],
        indexPath: URL? = nil
    ) throws -> LookupResult {
        if index.entries.isEmpty {
            throw VerifyError.indexEmpty(path: indexPath)
        }
        let normalizedPrefix = normalize(prefix: rawPrefix)
        let candidates = index.entries.filter { entry in
            normalize(hash: entry.identityHash).hasPrefix(normalizedPrefix)
        }
        switch candidates.count {
        case 0:
            let closest = nearestEntries(to: normalizedPrefix, in: index.entries, limit: 3)
            throw VerifyError.suggestionNotFound(
                prefix: rawPrefix,
                closest: closest.map(\.identityHash)
            )
        case 1:
            return LookupResult(entry: candidates[0], warnings: staleWarnings)
        default:
            let matched = candidates.prefix(5).map(\.identityHash)
            throw VerifyError.ambiguousPrefix(prefix: rawPrefix, matches: Array(matched))
        }
    }

    /// Resolve the on-disk index from an explicit path or the
    /// conventional `<packageRoot>/.swiftinfer/index.json` location.
    ///
    /// **Failure modes:**
    ///   - **Index file doesn't exist** → `.indexMissing(expectedPath:)`.
    ///     In the default-path flow `Verify.reindexIfNeeded` (V1.42.C.5)
    ///     rebuilds the index before this runs, so this throw is
    ///     normally only reached for an explicit `--index-path` that
    ///     doesn't exist (explicit paths are used as-is, never
    ///     auto-rebuilt).
    ///   - **Decode failure** propagates through as diagnostic warnings
    ///     plus an empty index, which then surfaces `.indexEmpty`.
    ///
    /// `staleWarnings` is populated when the index file's mtime is
    /// older than any `.swift` file under `<packageRoot>/Sources/`.
    /// Best-effort — silently returns an empty array on I/O errors.
    static func resolveIndex(
        packageRoot: URL,
        explicitIndexPath: URL?,
        now: String,
        fileSystem: FileSystemReader = DefaultFileSystemReader()
    ) throws -> ResolvedIndex {
        let path = explicitIndexPath ?? IndexStore.defaultPath(for: packageRoot)
        guard fileSystem.fileExists(atPath: path.path) else {
            throw VerifyError.indexMissing(expectedPath: path)
        }
        let loadResult = IndexStore.load(from: path, nowTimestamp: now, fileSystem: fileSystem)
        let staleWarnings: [String]
        if isStale(indexPath: path, packageRoot: packageRoot) {
            staleWarnings = [
                "index at \(path.path) appears stale (some Sources/**.swift mtimes are newer). "
                    + "Consider `swift-infer index --target <X>` to refresh; "
                    + "V1.42.C.1 proceeds with the existing index."
            ]
        } else {
            staleWarnings = []
        }
        return ResolvedIndex(
            index: loadResult.index,
            path: path,
            warnings: loadResult.warnings + staleWarnings
        )
    }

    // MARK: - Helpers

    /// `0xBC43` and `BC43` both normalize to `"bc43"`.
    private static func normalize(prefix: String) -> String {
        let stripped: String
        if prefix.hasPrefix("0x") || prefix.hasPrefix("0X") {
            stripped = String(prefix.dropFirst(2))
        } else {
            stripped = prefix
        }
        return stripped.lowercased()
    }

    /// `0xBC43359C0574816B` normalizes to `"bc43359c0574816b"`.
    private static func normalize(hash: String) -> String {
        normalize(prefix: hash)
    }

    /// The N entries whose identityHash is lexically closest to
    /// `normalizedPrefix`. Used only in the "no match" error path to
    /// help the user see what was nearby.
    private static func nearestEntries(
        to normalizedPrefix: String,
        in entries: [SemanticIndexEntry],
        limit: Int
    ) -> [SemanticIndexEntry] {
        let scored = entries.map { entry -> (entry: SemanticIndexEntry, distance: Int) in
            let normalized = normalize(hash: entry.identityHash)
            return (entry, sharedPrefixLength(normalized, normalizedPrefix))
        }
        let sorted = scored.sorted { lhs, rhs in
            if lhs.distance != rhs.distance {
                return lhs.distance > rhs.distance
            }
            return lhs.entry.identityHash < rhs.entry.identityHash
        }
        return sorted.prefix(limit).map(\.entry)
    }

    private static func sharedPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        let pairs = zip(lhs, rhs)
        var count = 0
        for (left, right) in pairs where left == right {
            count += 1
        }
        return count
    }

    /// Best-effort staleness probe: walks `<packageRoot>/Sources/`,
    /// returns `true` if any `.swift` file has an mtime newer than the
    /// index file's. Silently returns `false` on I/O errors so a
    /// transient FS hiccup doesn't block a verify call. V1.42.C.5 made
    /// this `internal` so `Verify.reindexIfNeeded` shares the one
    /// staleness definition rather than re-implementing it.
    static func isStale(indexPath: URL, packageRoot: URL) -> Bool {
        let fileManager = FileManager.default
        guard let indexAttrs = try? fileManager.attributesOfItem(atPath: indexPath.path),
              let indexMTime = indexAttrs[.modificationDate] as? Date else {
            return false
        }
        let sourcesRoot = packageRoot.appendingPathComponent("Sources")
        guard let enumerator = fileManager.enumerator(
            at: sourcesRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return false
        }
        for case let fileURL as URL in enumerator
        where fileURL.pathExtension == "swift" {
            guard let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let modified = attrs[.modificationDate] as? Date else {
                continue
            }
            if modified > indexMTime {
                return true
            }
        }
        return false
    }
}
