import Foundation
import SwiftInferCore

/// V1.72.B — disk-resident store for `.swiftinfer/post-acceptance-
/// outcomes.json`. Mirrors `VerifyEvidenceStore` / `DecisionsLoader`'s
/// two-shape API:
///
///   1. **Explicit override** — an explicit path. Missing / malformed
///      file produces a warning (the caller explicitly asked for it).
///   2. **Implicit lookup** — walk up from the working directory to
///      find `Package.swift`, then read
///      `<package-root>/.swiftinfer/post-acceptance-outcomes.json`. A
///      missing file is silent (outcomes accumulate over accept-check
///      runs); a malformed file produces a warning and falls back to
///      `PostAcceptanceOutcomeLog.empty`.
///
/// Deliberately a near-clone of `VerifyEvidenceStore` rather than a
/// shared generic — the project keeps `ConfigLoader` / `DecisionsLoader`
/// / `VocabularyLoader` / `VerifyEvidenceStore` as parallel concrete
/// loaders, and the post-acceptance outcomes file is a distinct
/// artifact with its own lifecycle (re-runs of `accept-check` against
/// the same accepted suggestion). The read path never throws — all
/// read failure modes flatten to `(PostAcceptanceOutcomeLog.empty,
/// [warnings])`. `write` IS throwing: it's an explicit persistence
/// gesture (the accept-check write path), and a silent failure would
/// be worse than a thrown error the CLI can surface. Atomic write so a
/// half-written file never appears on disk.
public enum PostAcceptanceOutcomesStore {

    public struct Result: Equatable {
        public let log: PostAcceptanceOutcomeLog
        public let warnings: [String]
        public let packageRoot: URL?

        public init(
            log: PostAcceptanceOutcomeLog,
            warnings: [String],
            packageRoot: URL?
        ) {
            self.log = log
            self.warnings = warnings
            self.packageRoot = packageRoot
        }
    }

    public static let conventionalRelativePath = ".swiftinfer/post-acceptance-outcomes.json"

    public static func load(
        startingFrom directory: URL,
        explicitPath: URL? = nil,
        fileSystem: FileSystemReader = DefaultFileSystemReader()
    ) -> Result {
        let packageRoot = findPackageRoot(startingFrom: directory, fileSystem: fileSystem)
        if let explicitPath {
            return loadExplicit(path: explicitPath, packageRoot: packageRoot, fileSystem: fileSystem)
        }
        return loadImplicit(packageRoot: packageRoot, fileSystem: fileSystem)
    }

    /// Write `log` to `path` atomically. Creates the parent directory
    /// chain (`.swiftinfer/`) if needed. JSON output is stable:
    /// `sortedKeys` + `prettyPrinted` so the file diffs cleanly across
    /// accept-check runs and ISO8601 dates parse on every platform.
    public static func write(_ log: PostAcceptanceOutcomeLog, to path: URL) throws {
        let data = try canonicalEncoder.encode(log)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: path, options: .atomic)
    }

    /// Default conventional path beneath `packageRoot`.
    public static func defaultPath(for packageRoot: URL) -> URL {
        packageRoot.appendingPathComponent(conventionalRelativePath)
    }

    // MARK: - Explicit + implicit paths

    private static func loadExplicit(
        path: URL,
        packageRoot: URL?,
        fileSystem: FileSystemReader
    ) -> Result {
        guard fileSystem.fileExists(atPath: path.path) else {
            return Result(
                log: .empty,
                warnings: ["post-acceptance-outcomes file not found at \(path.path)"],
                packageRoot: packageRoot
            )
        }
        return parse(at: path, packageRoot: packageRoot, fileSystem: fileSystem)
    }

    private static func loadImplicit(
        packageRoot: URL?,
        fileSystem: FileSystemReader
    ) -> Result {
        guard let packageRoot else {
            return Result(log: .empty, warnings: [], packageRoot: nil)
        }
        let path = defaultPath(for: packageRoot)
        guard fileSystem.fileExists(atPath: path.path) else {
            return Result(log: .empty, warnings: [], packageRoot: packageRoot)
        }
        return parse(at: path, packageRoot: packageRoot, fileSystem: fileSystem)
    }

    private static func parse(
        at path: URL,
        packageRoot: URL?,
        fileSystem: FileSystemReader
    ) -> Result {
        do {
            let data = try fileSystem.contents(of: path)
            let log = try canonicalDecoder.decode(PostAcceptanceOutcomeLog.self, from: data)
            var warnings: [String] = []
            if log.schemaVersion > PostAcceptanceOutcomeLog.currentSchemaVersion {
                warnings.append(
                    "post-acceptance-outcomes at \(path.path): file schemaVersion "
                        + "\(log.schemaVersion) is newer than "
                        + "v\(PostAcceptanceOutcomeLog.currentSchemaVersion); loading what we can"
                )
            }
            return Result(log: log, warnings: warnings, packageRoot: packageRoot)
        } catch let error as DecodingError {
            return Result(
                log: .empty,
                warnings: ["could not parse post-acceptance-outcomes at \(path.path): \(error)"],
                packageRoot: packageRoot
            )
        } catch {
            return Result(
                log: .empty,
                warnings: [
                    "could not read post-acceptance-outcomes at \(path.path): "
                        + error.localizedDescription
                ],
                packageRoot: packageRoot
            )
        }
    }

    // MARK: - JSON shape

    /// Encoder shared with `DecisionsLoader` / `VerifyEvidenceStore`:
    /// `sortedKeys` for stable diffs, `prettyPrinted` for human
    /// `git diff` review, ISO8601 dates for cross-platform parsing.
    static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let canonicalDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Walk-up

    /// Walk up parent directories looking for `Package.swift`. Same
    /// shape as `VerifyEvidenceStore.findPackageRoot` — kept as a
    /// private helper so the loaders stay independent (each can be
    /// invoked in isolation by tests without setting up the other's
    /// fixture tree).
    private static func findPackageRoot(
        startingFrom directory: URL,
        fileSystem: FileSystemReader
    ) -> URL? {
        var current = directory.standardizedFileURL
        while true {
            let manifest = current.appendingPathComponent("Package.swift")
            if fileSystem.fileExists(atPath: manifest.path) {
                return current
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent == current {
                return nil
            }
            current = parent
        }
    }
}
