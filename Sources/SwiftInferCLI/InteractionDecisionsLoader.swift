import Foundation
import SwiftInferCore

/// V2.0 — disk-resident decisions lookup for the interaction-
/// invariant accept-flow. Resolves
/// `.swiftinfer/interaction-decisions.json` with the same shape as
/// v1's `DecisionsLoader`:
///
/// 1. **Explicit override** — `accept-interaction --decisions <path>`
///    or `accept-check-interaction --decisions <path>`. Missing /
///    malformed file produces a warning.
/// 2. **Implicit lookup** — walk up from the target's directory to
///    find `Package.swift`, then read
///    `<packageRoot>/.swiftinfer/interaction-decisions.json`. Missing
///    is silent; malformed warns and falls back to
///    `InteractionDecisions.empty`.
public enum InteractionDecisionsLoader {

    public struct Result: Equatable {
        public let decisions: InteractionDecisions
        public let warnings: [String]
        public let packageRoot: URL?

        public init(
            decisions: InteractionDecisions,
            warnings: [String],
            packageRoot: URL?
        ) {
            self.decisions = decisions
            self.warnings = warnings
            self.packageRoot = packageRoot
        }
    }

    public static let conventionalRelativePath = ".swiftinfer/interaction-decisions.json"

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

    /// Write `decisions` atomically. Creates the parent directory
    /// chain on demand. Mirrors v1's `DecisionsLoader.write`.
    public static func write(
        _ decisions: InteractionDecisions,
        to path: URL
    ) throws {
        let data = try canonicalEncoder.encode(decisions)
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
                decisions: .empty,
                warnings: ["interaction-decisions file not found at \(path.path)"],
                packageRoot: packageRoot
            )
        }
        return parse(at: path, packageRoot: packageRoot)
    }

    private static func loadImplicit(packageRoot: URL?) -> Result {
        guard let packageRoot else {
            return Result(decisions: .empty, warnings: [], packageRoot: nil)
        }
        let path = defaultPath(for: packageRoot)
        guard FileManager.default.fileExists(atPath: path.path) else {
            return Result(decisions: .empty, warnings: [], packageRoot: packageRoot)
        }
        return parse(at: path, packageRoot: packageRoot)
    }

    private static func parse(at path: URL, packageRoot: URL?) -> Result {
        do {
            let data = try Data(contentsOf: path)
            let decisions = try canonicalDecoder.decode(InteractionDecisions.self, from: data)
            var warnings: [String] = []
            if decisions.schemaVersion > InteractionDecisions.currentSchemaVersion {
                warnings.append(
                    "interaction-decisions at \(path.path): file schemaVersion "
                        + "\(decisions.schemaVersion) is newer than "
                        + "v\(InteractionDecisions.currentSchemaVersion); loading what we can"
                )
            }
            return Result(decisions: decisions, warnings: warnings, packageRoot: packageRoot)
        } catch let error as DecodingError {
            return Result(
                decisions: .empty,
                warnings: ["could not parse interaction-decisions at \(path.path): \(error)"],
                packageRoot: packageRoot
            )
        } catch {
            return Result(
                decisions: .empty,
                warnings: [
                    "could not read interaction-decisions at \(path.path): "
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
