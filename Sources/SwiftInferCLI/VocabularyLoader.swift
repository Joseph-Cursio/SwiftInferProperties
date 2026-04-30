import Foundation
import SwiftInferCore

/// Disk-resident vocabulary lookup for `swift-infer discover`. Resolves
/// `.swiftinfer/vocabulary.json` per PRD v0.3 §4.5 with two paths:
///
/// 1. **Explicit override** — when the caller passes `--vocabulary <path>`
///    we use that exact path. A missing or malformed file produces a
///    warning (the user explicitly asked for it; silently falling back
///    would mask a typo).
/// 2. **Implicit lookup** — walk up from the discover target's directory
///    until a `Package.swift` is found, then read
///    `<package-root>/.swiftinfer/vocabulary.json`. A missing file is
///    silent (vocabulary is opt-in); a malformed file produces a warning
///    and falls back to `.empty`.
///
/// The loader never throws. All failure modes flatten to
/// `(Vocabulary.empty, [warningLines])`. Warnings are surfaced via the
/// CLI's `DiagnosticOutput` so they reach stderr without polluting the
/// byte-stable suggestion stream on stdout (PRD §16 reproducibility
/// guarantee).
public enum VocabularyLoader {

    /// Outcome of a single load attempt.
    public struct Result: Equatable {
        public let vocabulary: Vocabulary
        public let warnings: [String]

        public init(vocabulary: Vocabulary, warnings: [String]) {
            self.vocabulary = vocabulary
            self.warnings = warnings
        }
    }

    /// Conventional path of the project-level vocabulary file relative to
    /// the package root. Public so tests can construct fixture trees
    /// against the same constant the loader uses.
    public static let conventionalRelativePath = ".swiftinfer/vocabulary.json"

    /// Load vocabulary either from `explicitPath` (if non-nil) or by
    /// walking up from `directory` to find the package root and reading
    /// `.swiftinfer/vocabulary.json` next to `Package.swift`.
    public static func load(
        startingFrom directory: URL,
        explicitPath: URL? = nil,
        fileSystem: FileSystemReader = DefaultFileSystemReader()
    ) -> Result {
        if let explicitPath {
            return loadExplicit(path: explicitPath, fileSystem: fileSystem)
        }
        return loadImplicit(startingFrom: directory, fileSystem: fileSystem)
    }

    // MARK: - Internal paths

    private static func loadExplicit(path: URL, fileSystem: FileSystemReader) -> Result {
        guard fileSystem.fileExists(atPath: path.path) else {
            return Result(
                vocabulary: .empty,
                warnings: ["vocabulary file not found at \(path.path)"]
            )
        }
        return parse(at: path, fileSystem: fileSystem)
    }

    private static func loadImplicit(startingFrom directory: URL, fileSystem: FileSystemReader) -> Result {
        guard let packageRoot = findPackageRoot(startingFrom: directory, fileSystem: fileSystem) else {
            return Result(vocabulary: .empty, warnings: [])
        }
        let path = packageRoot.appendingPathComponent(conventionalRelativePath)
        guard fileSystem.fileExists(atPath: path.path) else {
            return Result(vocabulary: .empty, warnings: [])
        }
        return parse(at: path, fileSystem: fileSystem)
    }

    private static func parse(at path: URL, fileSystem: FileSystemReader) -> Result {
        do {
            let data = try fileSystem.contents(of: path)
            let vocabulary = try JSONDecoder().decode(Vocabulary.self, from: data)
            return Result(vocabulary: vocabulary, warnings: [])
        } catch {
            return Result(
                vocabulary: .empty,
                warnings: ["could not parse vocabulary at \(path.path): \(error.localizedDescription)"]
            )
        }
    }

    /// Walk up parent directories looking for `Package.swift`. Returns
    /// `nil` if the walk reaches the filesystem root without finding one
    /// — that's the "discover invoked outside a SwiftPM project" case
    /// where the implicit-lookup path is silently disabled.
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

/// Test seam over the two FileManager calls the loader makes. Production
/// code uses `DefaultFileSystemReader`; tests can supply a stub to mock
/// out walk-up behaviour without writing a fixture tree to disk.
public protocol FileSystemReader: Sendable {
    func fileExists(atPath: String) -> Bool
    func contents(of url: URL) throws -> Data
}

public struct DefaultFileSystemReader: FileSystemReader {
    public init() {}

    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func contents(of url: URL) throws -> Data {
        try Data(contentsOf: url)
    }
}
