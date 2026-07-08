import ArgumentParser
import Foundation

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

        @Flag(
            name: .long,
            help: "Property-test each law live (generates + runs a stdlib-only Swift script)."
        )
        public var verify: Bool = false

        public init() { /* no-op */ }

        public func run() throws {
            let properties = type.map { wanted in
                StandardLibraryProperties.all.filter { $0.type == wanted }
            } ?? StandardLibraryProperties.all

            guard verify else {
                print(KnownPropertiesRenderer.renderList(properties), terminator: "")
                return
            }

            let laws = properties.filter { $0.kind == .law }
            let program = KnownPropertiesRenderer.renderVerifyProgram(laws)
            let output = try Self.runSwiftScript(program)
            let results = KnownPropertiesRenderer.parseVerifyOutput(output)
            print(KnownPropertiesRenderer.renderList(properties, verifyResults: results), terminator: "")
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
