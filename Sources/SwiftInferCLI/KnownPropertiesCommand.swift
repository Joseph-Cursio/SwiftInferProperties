import ArgumentParser
import Foundation
import SwiftInferCore

/// V1.145 — `swift-infer known-properties`. Lists the built-in catalog of
/// known-true algebraic properties on standard-library types (plus the
/// famous caveats). With `--verify`, it generates a self-contained Swift
/// script that property-tests each law with sampled inputs and reports what
/// held — proving the catalog rather than asserting it.
///
/// This is universal engine knowledge, not per-project data: it never reads
/// or writes a project's `.swiftinfer/`.
extension SwiftInferCommand {

    public struct KnownProperties: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "known-properties",
            abstract: "List (and optionally verify) known algebraic properties on "
                + "standard-library types — a provable seed of ground-truth."
        )

        @Option(name: .long, help: "Only show properties for this type (e.g. 'Set', 'Array').")
        public var type: String?

        @Option(
            name: .long,
            help: """
            Scope to the standard-library types the target's source actually \
            uses (scans Sources/<target>; a best-effort heuristic).
            """
        )
        public var target: String?

        @Option(name: .long, help: "Override the working directory for the --target scan.")
        public var directory: String?

        @Flag(
            name: .long,
            help: "Property-test each law live (generates + runs a stdlib-only Swift script)."
        )
        public var verify: Bool = false

        public init() { /* no-op */ }

        public func run() throws {
            var properties = StandardLibraryProperties.all
            if let target {
                let used = Self.usedTypes(forTarget: target, directory: directory)
                properties = properties.filter { used.contains($0.type) }
            }
            if let type {
                properties = properties.filter { $0.type == type }
            }

            guard verify else {
                print(KnownPropertiesRenderer.renderList(properties), terminator: "")
                return
            }

            let laws = properties.filter { $0.kind == .law }
            // Partition: stdlib + Foundation laws run in the fast `swift`
            // interpreter; laws importing an external Apple package build a temp
            // package against the real releases. Splitting keeps the common
            // stdlib-only run fast — the package build fires only when an
            // external law is in scope.
            var results: [String: Bool] = [:]
            let stdlibLaws = laws.filter { !$0.needsPackage }
            if !stdlibLaws.isEmpty {
                let output = try Self.runSwiftScript(KnownPropertiesRenderer.renderVerifyProgram(stdlibLaws))
                results.merge(KnownPropertiesRenderer.parseVerifyOutput(output)) { _, updated in updated }
            }
            let packageLaws = laws.filter(\.needsPackage)
            if !packageLaws.isEmpty {
                results.merge(try KnownPropertiesPackageVerify.run(laws: packageLaws)) { _, updated in updated }
            }
            print(KnownPropertiesRenderer.renderList(properties, verifyResults: results), terminator: "")
        }

        /// Scan `Sources/<target>` for the standard-library types it uses.
        /// Best-effort: an unreadable/empty target warns and returns `[]` (so
        /// the filter shows nothing rather than everything).
        private static func usedTypes(forTarget target: String, directory: String?) -> Set<String> {
            let base = URL(fileURLWithPath: directory ?? ".")
                .appendingPathComponent("Sources")
                .appendingPathComponent(target)
            let files = SwiftSourceFiles.sorted(in: base)
            if files.isEmpty {
                FileHandle.standardError.write(
                    Data("warning: no Swift sources found under \(base.path)\n".utf8)
                )
                return []
            }
            let sources = files.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            let candidates = Set(StandardLibraryProperties.all.map(\.type))
            return StdlibTypeUsage.typesUsed(in: sources, among: candidates)
        }

        /// Write `source` to a temp `.swift` file and run it via the `swift`
        /// interpreter, returning stdout. Stdlib-only — no package needed.
        private static func runSwiftScript(_ source: String) throws -> String {
            let scriptURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("known-properties-\(UUID().uuidString).swift")
            try Data(source.utf8).write(to: scriptURL)
            defer { try? FileManager.default.removeItem(at: scriptURL) }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["swift", scriptURL.path]
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()   // discard compiler chatter
            try process.run()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        }
    }
}
