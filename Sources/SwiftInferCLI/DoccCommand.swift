import ArgumentParser
import Foundation
import SwiftInferCore

/// V1.142 — `swift-infer docc` subcommand. Emits DocC documentation for the
/// **verified** properties in `.swiftinfer/index.json` — those with a
/// `measured-bothPass` record in `.swiftinfer/verify-evidence.json`. See
/// `DoccPageBuilder` for the gate rationale.
///
/// Non-invasive by default: writes to `.swiftinfer/docc/` (tool-owned), not
/// the user's source tree. Point `--output` at a real `<Target>.docc/
/// Extensions/` directory to integrate the pages into a DocC catalog.
extension SwiftInferCommand {

    public struct Docc: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "docc",
            abstract: "Generate DocC docs for VERIFIED properties only "
                + "(measured `bothPass` in verify-evidence). Inferred-but-unverified "
                + "properties are never documented."
        )

        @Option(
            name: .long,
            help: "Override the package root for the index / evidence walk-up."
        )
        public var directory: String?

        @Option(
            name: .long,
            help: "Path to a specific index file (default: <package-root>/.swiftinfer/index.json)."
        )
        public var indexPath: String?

        @Option(
            name: .long,
            help: """
            Path to a specific verify-evidence file (default: \
            <package-root>/.swiftinfer/verify-evidence.json).
            """
        )
        public var evidencePath: String?

        @Option(
            name: .long,
            help: """
            Output directory for the generated `.md` pages (default: \
            <package-root>/.swiftinfer/docc). Point at a `<Target>.docc/Extensions` \
            dir to feed a DocC catalog directly.
            """
        )
        public var output: String?

        @Flag(
            name: .long,
            help: "List what would be written without creating files."
        )
        public var dryRun: Bool = false

        public init() { /* no-op */ }

        public func run() throws {
            let directoryURL = URL(fileURLWithPath: directory ?? ".")
            let explicitIndex = indexPath.map { URL(fileURLWithPath: $0) }
            guard let resolvedIndex = explicitIndex ?? Self.resolveIndexPath(startingFrom: directoryURL) else {
                print("No .swiftinfer/index.json found. Run `swift-infer index --target <X>` first.")
                return
            }
            let now = SwiftInferCommand.Index.isoTimestamp(from: Date())
            let indexLoad = IndexStore.load(from: resolvedIndex, nowTimestamp: now)
            let evidenceLoad = VerifyEvidenceStore.load(
                startingFrom: directoryURL,
                explicitPath: evidencePath.map { URL(fileURLWithPath: $0) }
            )
            for warning in indexLoad.warnings + evidenceLoad.warnings {
                FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
            }

            let verified = DoccPageBuilder.verifiedHashes(in: evidenceLoad.log)
            let properties = DoccPageBuilder.verifiedProperties(in: indexLoad.index, verified: verified)
            let pages = DoccPageBuilder.pages(from: properties)

            guard !pages.isEmpty else {
                print(
                    "No verified properties to document. "
                        + "Run `swift-infer verify --all-from-index` to produce measured evidence, then re-run."
                )
                return
            }

            // Default output is tool-owned (never mutate the source tree).
            let packageRoot = resolvedIndex.deletingLastPathComponent().deletingLastPathComponent()
            let outputDir = output.map { URL(fileURLWithPath: $0) }
                ?? packageRoot.appendingPathComponent(".swiftinfer/docc")

            if dryRun {
                print(Self.summary(properties: properties, pages: pages, outputDir: outputDir, dryRun: true))
                return
            }
            try DoccPageBuilder.write(pages, to: outputDir)
            print(Self.summary(properties: properties, pages: pages, outputDir: outputDir, dryRun: false))
        }

        static func summary(
            properties: [DoccProperty],
            pages: [DoccPage],
            outputDir: URL,
            dryRun: Bool
        ) -> String {
            let verb = dryRun ? "Would write" : "Wrote"
            var lines = [
                "\(verb) \(pages.count) DocC page(s) "
                    + "(\(properties.count) verified propert\(properties.count == 1 ? "y" : "ies")) "
                    + "→ \(outputDir.path)"
            ]
            for page in pages { lines.append("  \(page.fileName)") }
            return lines.joined(separator: "\n")
        }

        /// Walk up from `directory` to `Package.swift`, then the conventional
        /// index path beneath it. `nil` when no package root or no index.
        private static func resolveIndexPath(startingFrom directory: URL) -> URL? {
            let fileSystem = DefaultFileSystemReader()
            var current = directory.standardizedFileURL
            while true {
                let manifest = current.appendingPathComponent("Package.swift")
                if fileSystem.fileExists(atPath: manifest.path) {
                    let path = current.appendingPathComponent(IndexStore.conventionalRelativePath)
                    return fileSystem.fileExists(atPath: path.path) ? path : nil
                }
                let parent = current.deletingLastPathComponent().standardizedFileURL
                if parent == current { return nil }
                current = parent
            }
        }
    }
}
