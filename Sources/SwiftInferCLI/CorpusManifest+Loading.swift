import Foundation

// MARK: - Loading

extension CorpusManifest {

    enum LoadError: Error, CustomStringConvertible {
        case unreadable(path: String, underlying: Error)
        case unsupportedSchema(found: Int, supported: Int)

        var description: String {
            switch self {
            case let .unreadable(path, underlying):
                return "could not read the corpus manifest at '\(path)': \(underlying)"

            case let .unsupportedSchema(found, supported):
                return "corpus manifest declares schemaVersion \(found); this build "
                    + "understands \(supported)"
            }
        }
    }

    /// Load the manifest from a repo root.
    static func load(repositoryRoot: URL) throws -> Self {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        let manifest: Self
        do {
            manifest = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        } catch {
            throw LoadError.unreadable(path: url.path, underlying: error)
        }
        guard manifest.schemaVersion == currentSchemaVersion else {
            throw LoadError.unsupportedSchema(
                found: manifest.schemaVersion, supported: currentSchemaVersion
            )
        }
        return manifest
    }

    /// The entry with this id, or `nil`.
    func entry(id: String) -> Entry? {
        corpora.first { $0.id == id }
    }

    /// Every id, in manifest order — for an error message that lists what the caller could
    /// have typed instead.
    var identifiers: [String] {
        corpora.map(\.id)
    }

    /// Every apparatus named by any measurement, sorted. Used to validate `--apparatus` and to
    /// tell a caller what the corpus has actually been put through.
    var apparatuses: [String] {
        Set(corpora.flatMap(\.measurements).map(\.apparatus)).sorted()
    }

    /// Entries measured by `apparatus`, which is the question each of the four disjoint corpus
    /// lists used to answer on its own.
    func corpora(measuredBy apparatus: String) -> [Entry] {
        corpora.filter { entry in
            entry.measurements.contains { $0.apparatus == apparatus }
        }
    }
}
