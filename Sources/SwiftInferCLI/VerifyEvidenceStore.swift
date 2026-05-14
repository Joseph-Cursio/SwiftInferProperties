import Foundation
import SwiftInferCore

/// Disk-resident verify-evidence store for `swift-infer verify` (writer)
/// and `swift-infer discover` (reader — v1.64 workstream C). Resolves
/// `.swiftinfer/verify-evidence.json` with the same two shapes as
/// `DecisionsLoader`:
///
/// 1. **Explicit override** — an explicit path. A missing or malformed
///    file produces a warning (the caller explicitly asked for it).
/// 2. **Implicit lookup** — walk up from the working directory to find
///    `Package.swift`, then read
///    `<package-root>/.swiftinfer/verify-evidence.json`. A missing file
///    is silent (evidence is opt-in / accumulates across verify runs);
///    a malformed file produces a warning and falls back to
///    `VerifyEvidenceLog.empty`.
///
/// Deliberately a near-clone of `DecisionsLoader` rather than a shared
/// generic: the project keeps `ConfigLoader` / `DecisionsLoader` /
/// `VocabularyLoader` as parallel concrete loaders, and a verify-
/// evidence file is a distinct artifact with its own lifecycle. The
/// read path never throws — all read failure modes flatten to
/// `(VerifyEvidenceLog.empty, [warnings])`. `write` IS throwing: it's
/// an explicit persistence gesture (the `verify` write path), and a
/// silent write failure would be worse than a thrown error the CLI can
/// surface. Atomic write so a half-written file never appears on disk.
public enum VerifyEvidenceStore {

    public struct Result: Equatable {
        public let log: VerifyEvidenceLog
        public let warnings: [String]
        public let packageRoot: URL?

        public init(log: VerifyEvidenceLog, warnings: [String], packageRoot: URL?) {
            self.log = log
            self.warnings = warnings
            self.packageRoot = packageRoot
        }
    }

    public static let conventionalRelativePath = ".swiftinfer/verify-evidence.json"

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
    /// verify runs and ISO8601 dates parse on every platform.
    public static func write(_ log: VerifyEvidenceLog, to path: URL) throws {
        let data = try canonicalEncoder.encode(log)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: path, options: .atomic)
    }

    /// Default conventional path beneath `packageRoot`. Used by the
    /// `verify` write path and the `discover` reader when no explicit
    /// path is passed.
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
                warnings: ["verify-evidence file not found at \(path.path)"],
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
            let log = try canonicalDecoder.decode(VerifyEvidenceLog.self, from: data)
            var warnings: [String] = []
            if log.schemaVersion > VerifyEvidenceLog.currentSchemaVersion {
                warnings.append(
                    "verify-evidence at \(path.path): file schemaVersion "
                        + "\(log.schemaVersion) is newer than "
                        + "v\(VerifyEvidenceLog.currentSchemaVersion); loading what we can"
                )
            }
            return Result(log: log, warnings: warnings, packageRoot: packageRoot)
        } catch let error as DecodingError {
            return Result(
                log: .empty,
                warnings: ["could not parse verify-evidence at \(path.path): \(error)"],
                packageRoot: packageRoot
            )
        } catch {
            return Result(
                log: .empty,
                warnings: ["could not read verify-evidence at \(path.path): \(error.localizedDescription)"],
                packageRoot: packageRoot
            )
        }
    }

    // MARK: - JSON shape

    /// Encoder used for both the canonical persistence write AND the
    /// byte-stable goldens in tests. `sortedKeys` makes the file diff
    /// cleanly when records are appended; `prettyPrinted` keeps
    /// human-readability for `git diff` review; ISO8601 dates parse
    /// reliably across platforms. Matches `DecisionsLoader`'s encoder.
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
    /// shape as `DecisionsLoader.findPackageRoot` — kept as a private
    /// helper so the loaders stay independent (each can be invoked in
    /// isolation by tests without setting up the other's fixture tree).
    private static func findPackageRoot(startingFrom directory: URL, fileSystem: FileSystemReader) -> URL? {
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
