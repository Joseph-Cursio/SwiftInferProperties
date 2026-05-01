import Foundation
import SwiftInferCore

/// Disk-resident decisions lookup for `swift-infer discover --interactive`
/// + `swift-infer drift`. Resolves `.swiftinfer/decisions.json` per
/// PRD v0.4 §5.8 M6 with the same two shapes as `ConfigLoader`:
///
/// 1. **Explicit override** — `--decisions <path>`. Missing or malformed
///    file produces a warning (the user explicitly asked for it).
/// 2. **Implicit lookup** — walk up from the discover target's directory
///    to find `Package.swift`, then read
///    `<package-root>/.swiftinfer/decisions.json`. A missing file is
///    silent (decisions are opt-in / accumulate over time); a malformed
///    file produces a warning and falls back to `Decisions.empty`.
///
/// The loader never throws on read; all read failure modes flatten to
/// `(Decisions.empty, [warningLines])` matching `ConfigLoader`'s
/// "no panic on missing or corrupt" contract.
///
/// `write` IS throwing — it's an explicit user-driven persistence
/// gesture (the `--interactive` accept path), and silent write
/// failures would be worse than a thrown error the CLI can surface to
/// the user. Atomic write via `Data.write(to:options:.atomic)` so a
/// half-written decisions.json never appears on disk.
public enum DecisionsLoader {

    public struct Result: Equatable {
        public let decisions: Decisions
        public let warnings: [String]
        public let packageRoot: URL?

        public init(decisions: Decisions, warnings: [String], packageRoot: URL?) {
            self.decisions = decisions
            self.warnings = warnings
            self.packageRoot = packageRoot
        }
    }

    public static let conventionalRelativePath = ".swiftinfer/decisions.json"

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

    /// Write `decisions` to `path` atomically. Creates the parent
    /// directory chain (`.swiftinfer/`) if needed. JSON output is
    /// stable: `sortedKeys` + `prettyPrinted` so the file diffs
    /// cleanly across runs and ISO8601 dates parse on every platform.
    public static func write(
        _ decisions: Decisions,
        to path: URL
    ) throws {
        let data = try canonicalEncoder.encode(decisions)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: path, options: .atomic)
    }

    /// Default conventional path beneath `packageRoot`. Used by the
    /// CLI's `--interactive` accept flow when no explicit path is
    /// passed — mirrors the `--vocabulary` / `--config` resolution
    /// pattern.
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
                decisions: .empty,
                warnings: ["decisions file not found at \(path.path)"],
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
            return Result(decisions: .empty, warnings: [], packageRoot: nil)
        }
        let path = defaultPath(for: packageRoot)
        guard fileSystem.fileExists(atPath: path.path) else {
            return Result(decisions: .empty, warnings: [], packageRoot: packageRoot)
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
            let decisions = try canonicalDecoder.decode(Decisions.self, from: data)
            var warnings: [String] = []
            if decisions.schemaVersion > Decisions.currentSchemaVersion {
                warnings.append(
                    "decisions at \(path.path): file schemaVersion "
                        + "\(decisions.schemaVersion) is newer than "
                        + "v\(Decisions.currentSchemaVersion); loading what we can"
                )
            }
            return Result(decisions: decisions, warnings: warnings, packageRoot: packageRoot)
        } catch let error as DecodingError {
            return Result(
                decisions: .empty,
                warnings: ["could not parse decisions at \(path.path): \(error)"],
                packageRoot: packageRoot
            )
        } catch {
            return Result(
                decisions: .empty,
                warnings: ["could not read decisions at \(path.path): \(error.localizedDescription)"],
                packageRoot: packageRoot
            )
        }
    }

    // MARK: - JSON shape

    /// Encoder used for both the canonical persistence write AND the
    /// byte-stable goldens in tests. `sortedKeys` makes the file diff
    /// cleanly when records are appended; `prettyPrinted` keeps
    /// human-readability for `git diff` review; ISO8601 dates parse
    /// reliably across platforms.
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
    /// shape as `ConfigLoader.findPackageRoot` — kept as a private
    /// helper here so the loaders stay independent (each can be
    /// invoked in isolation by tests without setting up the other's
    /// fixture tree).
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
