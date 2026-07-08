import ArgumentParser
import Foundation
import SwiftInferCore

/// V1.149 — `swift-infer report`. A read-only, one-glance overview folding the
/// SemanticIndex (algebraic + interaction), the measured-verify evidence, and
/// the cross-type insights into a single status view. Reads only; never writes.
extension SwiftInferCommand {

    public struct Report: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "report",
            abstract: "One-glance overview of what SwiftInfer knows about this project "
                + "(index + verify evidence + cross-type insights). Read-only."
        )

        @Option(name: .long, help: "Override the package root for the index walk-up.")
        public var directory: String?

        @Option(
            name: .long,
            help: "Path to a specific index file (default: <package-root>/.swiftinfer/index.json)."
        )
        public var indexPath: String?

        public init() { /* no-op */ }

        public func run() {
            let directoryURL = URL(fileURLWithPath: directory ?? ".")
            let explicitIndex = indexPath.map { URL(fileURLWithPath: $0) }
            guard let resolvedIndex = explicitIndex ?? Self.resolveIndexPath(startingFrom: directoryURL) else {
                print("No .swiftinfer/index.json found. Run `swift-infer index --target <X>` first.")
                return
            }
            let now = SwiftInferCommand.Index.isoTimestamp(from: Date())
            let indexLoad = IndexStore.load(from: resolvedIndex, nowTimestamp: now)
            let evidenceLoad = VerifyEvidenceStore.load(startingFrom: directoryURL)
            for warning in indexLoad.warnings + evidenceLoad.warnings {
                FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
            }
            let insights = InsightsBuilder.groups(
                in: indexLoad.index,
                minTypes: 2,
                includeTiers: ["Verified", "Strong", "Likely"]
            )
            print(
                ReportRenderer.render(
                    index: indexLoad.index,
                    evidence: evidenceLoad.log,
                    insights: insights
                ),
                terminator: ""
            )
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
