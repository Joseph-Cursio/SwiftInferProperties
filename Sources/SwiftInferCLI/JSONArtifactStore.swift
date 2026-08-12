import Foundation
import SwiftInferCore

/// A `.swiftinfer/` JSON artifact: something the tool writes on an explicit
/// user gesture and reads back on a later run.
///
/// Five of these exist, and before this protocol each carried its own copy of
/// the same ~155-line loader — `BaselineLoader`, `DecisionsLoader`,
/// `VerifyEvidenceStore`, and the two `Interaction*` twins. The copies were
/// deliberate and said so: `BaselineLoader.write` was documented as using the
/// *"Same canonical JSON encoder as `DecisionsLoader`'s persistence path"* and
/// `defaultPath(for:)` as one that *"mirrors the M6.1
/// `DecisionsLoader.defaultPath(for:)`"*. Five files agreeing by hand is a
/// claim nothing checks; the encoder settings, the walk-up, the
/// missing-vs-malformed split and the schema-version warning are now one
/// implementation that cannot drift apart.
///
/// What genuinely differed was five values, and they are exactly the
/// requirements below.
///
/// ## This reverses a decision that was written down
///
/// `VerifyEvidenceStore` argued the opposite in its own doc comment, and the
/// argument deserves restating rather than deleting: it was *"deliberately a
/// near-clone of `DecisionsLoader` rather than a shared generic"*, because
/// *"the project keeps `ConfigLoader` / `DecisionsLoader` / `VocabularyLoader`
/// as parallel concrete loaders, and a verify-evidence file is a distinct
/// artifact with its own lifecycle."*
///
/// Both halves are answered rather than overruled. **The lifecycles stay
/// distinct** — each artifact keeps its own type, its own conventional path,
/// its own noun in warnings, and its own `Result` with the field name its
/// callers read; what is shared is the file mechanics, which never differed.
/// **The cited precedent is narrower than it reads**: `ConfigLoader` and
/// `VocabularyLoader` are not artifacts of this shape at all — one parses TOML
/// config, the other owns `FileSystemReader` itself — so the parallel-loaders
/// convention was really about `DecisionsLoader` and its copies, which is the
/// duplication rather than a reason for it.
///
/// What changed since is arithmetic: the two loaders became five, and the
/// comments began asserting agreement between files that nothing checked.
public protocol JSONArtifact: Codable, Equatable, Sendable {
    /// Returned whenever the file is absent or unreadable. Loading never
    /// panics — a missing artifact is the normal first-run state.
    static var empty: Self { get }

    /// The newest schema this build understands.
    static var currentSchemaVersion: Int { get }

    /// The schema the file on disk was written with.
    var schemaVersion: Int { get }

    /// How this artifact is named in warnings — `baseline`,
    /// `interaction-decisions`. Distinct from the filename because the
    /// messages are asserted verbatim by tests and read by users.
    static var artifactNoun: String { get }

    /// Path beneath the package root, e.g. `.swiftinfer/baseline.json`.
    static var conventionalRelativePath: String { get }
}

extension Baseline: JSONArtifact {
    public static var artifactNoun: String { "baseline" }
    public static var conventionalRelativePath: String { ".swiftinfer/baseline.json" }
}

extension Decisions: JSONArtifact {
    public static var artifactNoun: String { "decisions" }
    public static var conventionalRelativePath: String { ".swiftinfer/decisions.json" }
}

extension VerifyEvidenceLog: JSONArtifact {
    public static var artifactNoun: String { "verify-evidence" }
    public static var conventionalRelativePath: String { ".swiftinfer/verify-evidence.json" }
}

extension InteractionBaseline: JSONArtifact {
    public static var artifactNoun: String { "interaction-baseline" }
    public static var conventionalRelativePath: String { ".swiftinfer/interaction-baseline.json" }
}

extension InteractionDecisions: JSONArtifact {
    public static var artifactNoun: String { "interaction-decisions" }
    public static var conventionalRelativePath: String { ".swiftinfer/interaction-decisions.json" }
}

/// The canonical coder pair every `.swiftinfer/` artifact is read and written
/// with. Deliberately non-generic: the settings do not depend on the artifact,
/// so all five share one instance rather than one per specialisation — and
/// Swift forbids static stored properties in a generic type regardless.
enum CanonicalJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// The one load/write implementation the five `.swiftinfer/` artifacts share.
///
/// **Read flattens, write throws**, and the asymmetry is deliberate: a missing
/// or corrupt artifact yields `(.empty, [warnings])` because a first run has no
/// file and a stale one should not stop the tool, while writing happens only on
/// an explicit gesture like `discover --update-baseline`, where a silent
/// failure would be worse than a thrown error.
///
/// **Missing and malformed are different**, and so is explicit versus implicit.
/// An explicit `--baseline <path>` that does not exist *warns* — the user named
/// a file and deserves to hear it is not there. The implicit lookup missing is
/// *silent*, because that is simply the state before the first write. Malformed
/// warns either way.
public enum JSONArtifactStore<Artifact: JSONArtifact> {
    public struct Result: Equatable {
        public let artifact: Artifact
        public let warnings: [String]
        public let packageRoot: URL?

        public init(artifact: Artifact, warnings: [String], packageRoot: URL?) {
            self.artifact = artifact
            self.warnings = warnings
            self.packageRoot = packageRoot
        }
    }

    public static var conventionalRelativePath: String { Artifact.conventionalRelativePath }

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

    /// Write `artifact` to `path` atomically, creating the `.swiftinfer/` chain
    /// if needed. `sortedKeys` + `prettyPrinted` so the file diffs cleanly
    /// across runs — the M6 plan's "byte-stable across re-saves" bar.
    public static func write(_ artifact: Artifact, to path: URL) throws {
        let data = try CanonicalJSON.encoder.encode(artifact)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: path, options: .atomic)
    }

    public static func defaultPath(for packageRoot: URL) -> URL {
        packageRoot.appendingPathComponent(Artifact.conventionalRelativePath)
    }

    // MARK: - Explicit + implicit paths

    private static func loadExplicit(
        path: URL,
        packageRoot: URL?,
        fileSystem: FileSystemReader
    ) -> Result {
        guard fileSystem.fileExists(atPath: path.path) else {
            return Result(
                artifact: .empty,
                warnings: ["\(Artifact.artifactNoun) file not found at \(path.path)"],
                packageRoot: packageRoot
            )
        }
        return parse(at: path, packageRoot: packageRoot, fileSystem: fileSystem)
    }

    private static func loadImplicit(packageRoot: URL?, fileSystem: FileSystemReader) -> Result {
        guard let packageRoot else {
            return Result(artifact: .empty, warnings: [], packageRoot: nil)
        }
        let path = defaultPath(for: packageRoot)
        guard fileSystem.fileExists(atPath: path.path) else {
            return Result(artifact: .empty, warnings: [], packageRoot: packageRoot)
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
            let artifact = try CanonicalJSON.decoder.decode(Artifact.self, from: data)
            var warnings: [String] = []
            // A newer file is read, not rejected: the fields this build knows
            // still decode, and refusing the whole artifact would lose them.
            if artifact.schemaVersion > Artifact.currentSchemaVersion {
                warnings.append(
                    "\(Artifact.artifactNoun) at \(path.path): file schemaVersion "
                        + "\(artifact.schemaVersion) is newer than "
                        + "v\(Artifact.currentSchemaVersion); loading what we can"
                )
            }
            return Result(artifact: artifact, warnings: warnings, packageRoot: packageRoot)
        } catch let error as DecodingError {
            // `DecodingError` is separated from the general case because its
            // description names the offending key and type, which is the whole
            // diagnosis; `localizedDescription` on it says only "data corrupted".
            return Result(
                artifact: .empty,
                warnings: ["could not parse \(Artifact.artifactNoun) at \(path.path): \(error)"],
                packageRoot: packageRoot
            )
        } catch {
            return Result(
                artifact: .empty,
                warnings: [
                    "could not read \(Artifact.artifactNoun) at \(path.path): "
                        + error.localizedDescription
                ],
                packageRoot: packageRoot
            )
        }
    }

    // MARK: - Walk-up

    /// Walk up parent directories looking for `Package.swift`.
    ///
    /// Each loader used to keep a private copy of this, documented as being so
    /// *"the loaders stay independent (each can be invoked in isolation by
    /// tests without setting up the others' fixture trees)"*. That property is
    /// unchanged here — it came from the function being self-contained and
    /// taking its file system as an argument, not from there being five of it.
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
