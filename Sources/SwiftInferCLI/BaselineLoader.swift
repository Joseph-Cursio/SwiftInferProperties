import Foundation
import SwiftInferCore

/// Disk-resident baseline lookup for `swift-infer drift` (M6.5).
/// Resolves `.swiftinfer/baseline.json` per PRD v0.4 §5.8 M6 with the
/// same shape as `DecisionsLoader` (M6.1) and `ConfigLoader` (M2):
///
/// 1. **Explicit override** — `drift --baseline <path>`. Missing or
///    malformed file produces a warning.
/// 2. **Implicit lookup** — walk up from the discover target's
///    directory to find `Package.swift`, then read
///    `<package-root>/.swiftinfer/baseline.json`. Missing file is
///    silent; malformed file warns and falls back to `Baseline.empty`.
///
/// Symmetric with `DecisionsLoader`: read flattens to
/// `(Baseline.empty, [warningLines])` (no panic on missing/corrupt);
/// write is throwing (explicit user gesture via `discover
/// --update-baseline`, silent failures would be worse than a thrown
/// error). Atomic write via `Data.write(to:options:.atomic)`.
public enum BaselineLoader {

    public struct Result: Equatable {
        public let baseline: Baseline
        public let warnings: [String]
        public let packageRoot: URL?

        public init(baseline: Baseline, warnings: [String], packageRoot: URL?) {
            self.baseline = baseline
            self.warnings = warnings
            self.packageRoot = packageRoot
        }
    }

    public static let conventionalRelativePath = ".swiftinfer/baseline.json"

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

    /// Write `baseline` to `path` atomically. Creates the parent
    /// directory chain (`.swiftinfer/`) if needed. Same canonical
    /// JSON encoder as `DecisionsLoader`'s persistence path —
    /// `sortedKeys` + `prettyPrinted` for clean diffs across runs.
    public static func write(
        _ baseline: Baseline,
        to path: URL
    ) throws {
        let data = try canonicalEncoder.encode(baseline)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: path, options: .atomic)
    }

    /// Default conventional path beneath `packageRoot`. Used by the
    /// CLI's `discover --update-baseline` flow when no explicit path
    /// is passed — mirrors the M6.1 `DecisionsLoader.defaultPath(for:)`.
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
                baseline: .empty,
                warnings: ["baseline file not found at \(path.path)"],
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
            return Result(baseline: .empty, warnings: [], packageRoot: nil)
        }
        let path = defaultPath(for: packageRoot)
        guard fileSystem.fileExists(atPath: path.path) else {
            return Result(baseline: .empty, warnings: [], packageRoot: packageRoot)
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
            let baseline = try canonicalDecoder.decode(Baseline.self, from: data)
            var warnings: [String] = []
            if baseline.schemaVersion > Baseline.currentSchemaVersion {
                warnings.append(
                    "baseline at \(path.path): file schemaVersion "
                        + "\(baseline.schemaVersion) is newer than "
                        + "v\(Baseline.currentSchemaVersion); loading what we can"
                )
            }
            return Result(baseline: baseline, warnings: warnings, packageRoot: packageRoot)
        } catch let error as DecodingError {
            return Result(
                baseline: .empty,
                warnings: ["could not parse baseline at \(path.path): \(error)"],
                packageRoot: packageRoot
            )
        } catch {
            return Result(
                baseline: .empty,
                warnings: ["could not read baseline at \(path.path): \(error.localizedDescription)"],
                packageRoot: packageRoot
            )
        }
    }

    // MARK: - JSON shape

    /// Same canonical encoder shape as `DecisionsLoader` so both
    /// `.swiftinfer/` artifacts diff identically and the M6 plan's
    /// "byte-stable across re-saves" acceptance bar (a) and (b) share
    /// one formatting convention. Baseline doesn't carry dates so
    /// `dateEncodingStrategy` is moot here, but kept for symmetry.
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
    /// shape as `DecisionsLoader.findPackageRoot` and
    /// `ConfigLoader.findPackageRoot` — kept as a private helper so
    /// the loaders stay independent (each can be invoked in isolation
    /// by tests without setting up the others' fixture trees).
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
