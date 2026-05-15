import Foundation
import SwiftInferCore

/// V2.0 accept-check follow-up — disk-resident store for
/// `.swiftinfer/interaction-post-acceptance-outcomes.json`. Same
/// shape as v1's `PostAcceptanceOutcomesStore` but keyed on the
/// interaction-decisions surface.
public enum InteractionPostAcceptanceOutcomesStore {

    public struct Result: Equatable {
        public let log: InteractionPostAcceptanceOutcomeLog
        public let warnings: [String]
        public let packageRoot: URL?

        public init(
            log: InteractionPostAcceptanceOutcomeLog,
            warnings: [String],
            packageRoot: URL?
        ) {
            self.log = log
            self.warnings = warnings
            self.packageRoot = packageRoot
        }
    }

    public static let conventionalRelativePath =
        ".swiftinfer/interaction-post-acceptance-outcomes.json"

    public static func load(
        startingFrom directory: URL,
        explicitPath: URL? = nil
    ) -> Result {
        let packageRoot = findPackageRoot(startingFrom: directory)
        let path = explicitPath ?? packageRoot.map(defaultPath(for:))
        guard let path else {
            return Result(log: .empty, warnings: [], packageRoot: nil)
        }
        guard FileManager.default.fileExists(atPath: path.path) else {
            // Missing → silent (empty log). Same posture as
            // BaselineLoader / InteractionDecisionsLoader.
            return Result(log: .empty, warnings: [], packageRoot: packageRoot)
        }
        return parse(at: path, packageRoot: packageRoot)
    }

    public static func write(
        _ log: InteractionPostAcceptanceOutcomeLog,
        to path: URL
    ) throws {
        let data = try canonicalEncoder.encode(log)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: path, options: .atomic)
    }

    public static func defaultPath(for packageRoot: URL) -> URL {
        packageRoot.appendingPathComponent(conventionalRelativePath)
    }

    private static func parse(at path: URL, packageRoot: URL?) -> Result {
        do {
            let data = try Data(contentsOf: path)
            let log = try canonicalDecoder.decode(
                InteractionPostAcceptanceOutcomeLog.self,
                from: data
            )
            var warnings: [String] = []
            if log.schemaVersion > InteractionPostAcceptanceOutcomeLog.currentSchemaVersion {
                warnings.append(
                    "interaction-post-acceptance-outcomes at \(path.path): file "
                        + "schemaVersion \(log.schemaVersion) is newer than "
                        + "v\(InteractionPostAcceptanceOutcomeLog.currentSchemaVersion); "
                        + "loading what we can"
                )
            }
            return Result(log: log, warnings: warnings, packageRoot: packageRoot)
        } catch let error as DecodingError {
            return Result(
                log: .empty,
                warnings: ["could not parse interaction-post-acceptance-outcomes "
                    + "at \(path.path): \(error)"],
                packageRoot: packageRoot
            )
        } catch {
            return Result(
                log: .empty,
                warnings: ["could not read interaction-post-acceptance-outcomes "
                    + "at \(path.path): \(error.localizedDescription)"],
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
