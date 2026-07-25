import Foundation
import SwiftInferCore

/// Disk-resident config lookup for `swift-infer discover`. Resolves
/// `.swiftinfer/config.toml` per PRD §5.8 (M2) with the same two
/// shapes as `VocabularyLoader`:
///
/// 1. **Explicit override** — `--config <path>`. Missing or malformed
///    file produces a warning (the user explicitly asked for it).
/// 2. **Implicit lookup** — walk up from the discover target's directory
///    to find `Package.swift`, then read
///    `<package-root>/.swiftinfer/config.toml`. A missing file is
///    silent (config is opt-in); a malformed file produces a warning
///    and falls back to `Config.defaults`.
///
/// Decoding is best-effort: unknown sections and unknown keys are
/// silently ignored to leave room for M3+ knobs without breaking older
/// loaders. A *known* key with the wrong value type produces a warning
/// and that key stays at its default while the rest of the config
/// loads.
///
/// The loader never throws; all failure modes flatten to
/// `(Config.defaults, [warningLines])`.
public enum ConfigLoader {

    public struct Result: Equatable {
        public let config: Config
        public let warnings: [String]
        /// The package root the loader walked up to, when one was found.
        /// The CLI uses this to resolve relative `vocabularyPath` strings
        /// against — `nil` when discover was invoked outside a SwiftPM
        /// project (silent-defaults case).
        public let packageRoot: URL?

        public init(config: Config, warnings: [String], packageRoot: URL?) {
            self.config = config
            self.warnings = warnings
            self.packageRoot = packageRoot
        }
    }

    public static let conventionalRelativePath = ".swiftinfer/config.toml"

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

    // MARK: - Explicit + implicit paths

    private static func loadExplicit(
        path: URL,
        packageRoot: URL?,
        fileSystem: FileSystemReader
    ) -> Result {
        guard fileSystem.fileExists(atPath: path.path) else {
            return Result(
                config: .defaults,
                warnings: ["config file not found at \(path.path)"],
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
            return Result(config: .defaults, warnings: [], packageRoot: nil)
        }
        let path = packageRoot.appendingPathComponent(conventionalRelativePath)
        guard fileSystem.fileExists(atPath: path.path) else {
            return Result(config: .defaults, warnings: [], packageRoot: packageRoot)
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
            guard let text = String(bytes: data, encoding: .utf8) else {
                return Result(
                    config: .defaults,
                    warnings: ["could not decode config at \(path.path) as UTF-8"],
                    packageRoot: packageRoot
                )
            }
            let tree = try MinimalTOMLParser.parse(text)
            return decode(tree, from: path, packageRoot: packageRoot)
        } catch let error as TOMLParseError {
            return Result(
                config: .defaults,
                warnings: ["could not parse config at \(path.path): \(error.description)"],
                packageRoot: packageRoot
            )
        } catch {
            return Result(
                config: .defaults,
                warnings: ["could not read config at \(path.path): \(error.localizedDescription)"],
                packageRoot: packageRoot
            )
        }
    }

    // MARK: - Decoding

    /// Project the TOML tree onto a `Config` value. Unknown sections and
    /// keys are silently ignored; known keys with wrong types are
    /// warned-and-skipped so the rest of the file still loads.
    private static func decode(
        _ tree: [String: [String: TOMLValue]],
        from path: URL,
        packageRoot: URL?
    ) -> Result {
        let discover = tree["discover"] ?? [:]
        var warnings: [String] = []
        let reader = KeyReader(discover: discover, path: path)

        let config = Config(
            includePossible: reader.boolean(
                "includePossible", default: Config.defaults.includePossible, into: &warnings
            ),
            vocabularyPath: reader.string(
                "vocabularyPath", default: Config.defaults.vocabularyPath, into: &warnings
            ),
            // V1.32.C — Domain Template Packs. Comma-separated string form
            // (the MinimalTOMLParser doesn't support arrays in v1).
            packs: reader.string("packs", default: Config.defaults.packs, into: &warnings),
            // On by default; a project that finds the advisory noisy turns it off
            // here rather than remembering `--no-docstring-advice` on every run.
            docstringAdvice: reader.boolean(
                "docstringAdvice", default: Config.defaults.docstringAdvice, into: &warnings
            )
        )
        return Result(config: config, warnings: warnings, packageRoot: packageRoot)
    }

    /// Typed reads of one `[discover]` key, with the warn-and-keep-the-default
    /// behaviour every key shares.
    ///
    /// Extracted from `decode` because that function grew a branch per key —
    /// four keys of copy-pasted `switch` put it over the complexity and
    /// body-length caps. Each new key is now one line there rather than nine.
    private struct KeyReader {
        let discover: [String: TOMLValue]
        let path: URL

        func boolean(_ key: String, default fallback: Bool, into warnings: inout [String]) -> Bool {
            switch discover[key] {
            case .boolean(let bool):
                return bool

            case .string:
                warnings.append(typeWarning(key, expected: "boolean"))
                return fallback

            case nil:
                return fallback
            }
        }

        func string(
            _ key: String, default fallback: String?, into warnings: inout [String]
        ) -> String? {
            switch discover[key] {
            case .string(let str):
                return str

            case .boolean:
                warnings.append(typeWarning(key, expected: "string"))
                return fallback

            case nil:
                return fallback
            }
        }

        private func typeWarning(_ key: String, expected: String) -> String {
            "config at \(path.path): expected \(expected) for [discover].\(key), ignoring"
        }
    }

    // MARK: - Walk-up

    /// Walk up parent directories looking for `Package.swift`. Same
    /// shape as `VocabularyLoader.findPackageRoot` — kept as a private
    /// helper here so the two loaders stay independent (each can be
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
