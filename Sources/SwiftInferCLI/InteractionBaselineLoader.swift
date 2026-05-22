import Foundation
import SwiftInferCore

/// V2.0 M10 — disk-resident baseline lookup for `swift-infer
/// drift-interaction`. Resolves
/// `.swiftinfer/interaction-baseline.json` with the same load shape
/// as v1's `BaselineLoader`:
///
/// 1. **Explicit override** — `drift-interaction --baseline <path>`.
///    Missing or malformed file produces a warning.
/// 2. **Implicit lookup** — walk up from the target's directory to
///    find `Package.swift`, then read
///    `<packageRoot>/.swiftinfer/interaction-baseline.json`. Missing
///    is silent; malformed warns and falls back to
///    `InteractionBaseline.empty`.
public enum InteractionBaselineLoader {

    public struct Result: Equatable {
        public let baseline: InteractionBaseline
        public let warnings: [String]
        public let packageRoot: URL?

        public init(
            baseline: InteractionBaseline,
            warnings: [String],
            packageRoot: URL?
        ) {
            self.baseline = baseline
            self.warnings = warnings
            self.packageRoot = packageRoot
        }
    }

    public static let conventionalRelativePath = ".swiftinfer/interaction-baseline.json"

    public static func load(
        startingFrom directory: URL,
        explicitPath: URL? = nil
    ) -> Result {
        let packageRoot = findPackageRoot(startingFrom: directory)
        if let explicitPath {
            return loadExplicit(path: explicitPath, packageRoot: packageRoot)
        }
        return loadImplicit(packageRoot: packageRoot)
    }

    /// Write `baseline` atomically to `path`. Creates the parent
    /// directory chain on demand. Mirrors v1's `BaselineLoader.write`
    /// — `sortedKeys` + `prettyPrinted` for clean diffs across runs.
    public static func write(
        _ baseline: InteractionBaseline,
        to path: URL
    ) throws {
        let data = try canonicalEncoder.encode(baseline)
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

    // MARK: - Internals

    private static func loadExplicit(path: URL, packageRoot: URL?) -> Result {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return Result(
                baseline: .empty,
                warnings: ["interaction-baseline file not found at \(path.path)"],
                packageRoot: packageRoot
            )
        }
        return parse(at: path, packageRoot: packageRoot)
    }

    private static func loadImplicit(packageRoot: URL?) -> Result {
        guard let packageRoot else {
            return Result(baseline: .empty, warnings: [], packageRoot: nil)
        }
        let path = defaultPath(for: packageRoot)
        guard FileManager.default.fileExists(atPath: path.path) else {
            return Result(baseline: .empty, warnings: [], packageRoot: packageRoot)
        }
        return parse(at: path, packageRoot: packageRoot)
    }

    private static func parse(at path: URL, packageRoot: URL?) -> Result {
        do {
            let data = try Data(contentsOf: path)
            let baseline = try canonicalDecoder.decode(InteractionBaseline.self, from: data)
            var warnings: [String] = []
            if baseline.schemaVersion > InteractionBaseline.currentSchemaVersion {
                warnings.append(
                    "interaction-baseline at \(path.path): file schemaVersion "
                        + "\(baseline.schemaVersion) is newer than "
                        + "v\(InteractionBaseline.currentSchemaVersion); loading what we can"
                )
            }
            return Result(baseline: baseline, warnings: warnings, packageRoot: packageRoot)
        } catch let error as DecodingError {
            return Result(
                baseline: .empty,
                warnings: ["could not parse interaction-baseline at \(path.path): \(error)"],
                packageRoot: packageRoot
            )
        } catch {
            return Result(
                baseline: .empty,
                warnings: [
                    "could not read interaction-baseline at \(path.path): "
                        + error.localizedDescription
                ],
                packageRoot: packageRoot
            )
        }
    }

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

    private static func findPackageRoot(startingFrom directory: URL) -> URL? {
        var current = directory.standardizedFileURL
        while true {
            let manifest = current.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: manifest.path) {
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
