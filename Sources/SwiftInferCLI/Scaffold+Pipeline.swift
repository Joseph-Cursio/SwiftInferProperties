import ArgumentParser
import Foundation
import PropertyLawCore
import SwiftInferCore

/// Pure-function result of the scaffold pipeline — testable without IO.
public struct ScaffoldOutcome: Equatable {
    /// The assembled scaffold file, or `nil` when nothing is scaffoldable.
    public let fileText: String?
    /// Names of the types that got a scaffold stub, sorted.
    public let scaffoldedTypeNames: [String]

    public init(fileText: String?, scaffoldedTypeNames: [String]) {
        self.fileText = fileText
        self.scaffoldedTypeNames = scaffoldedTypeNames
    }
}

extension SwiftInferCommand {

    /// `swift-infer scaffold` — emit best-effort `gen()` stubs for types that
    /// can't be fully auto-derived. Slots PropertyLawCore can derive
    /// (raw / composite / nested / known value / typealias) are filled; the
    /// rest are left as `<#Generator<T>#>` placeholders for the developer.
    /// Read-only over source; writes only the opt-in scaffold file.
    public struct Scaffold: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "scaffold",
            abstract: "Emit best-effort gen() stubs (with <#...#> placeholders) "
                + "for types that can't be fully auto-derived."
        )

        @Option(name: .long, help: "Name of the SwiftPM target to scan (Sources/<target>/).")
        public var target: String

        @Option(name: .long, help: "Override the test directory TestLifter scans.")
        public var testDir: String?

        @Option(name: .long, help: """
            Output path for the scaffold file. Defaults to \
            Tests/Generated/SwiftInfer/Scaffolds.generated.swift.
            """)
        public var output: String?

        public init() { /* no-op */ }

        public func run() async throws {
            let directory = URL(fileURLWithPath: "Sources").appendingPathComponent(target)
            let outcome = try Self.scaffold(
                directory: directory,
                testDirectory: testDir.map { URL(fileURLWithPath: $0) },
                diagnostics: PrintDiagnosticOutput()
            )
            guard let fileText = outcome.fileText else {
                print("scaffold: no partially-derivable types — nothing to write.")
                return
            }
            let outputURL = output.map { URL(fileURLWithPath: $0) }
                ?? Self.defaultOutputURL(packageRoot: nil)
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileText.write(to: outputURL, atomically: true, encoding: .utf8)
            print("scaffold: wrote \(outcome.scaffoldedTypeNames.count) stub(s) → \(outputURL.path)")
        }

        /// Pure pipeline — discover the type universe, derive each type, and
        /// scaffold the `.todo` ones. Exposed for tests (no IO).
        public static func scaffold(
            directory: URL,
            testDirectory: URL? = nil,
            diagnostics: any DiagnosticOutput = PrintDiagnosticOutput()
        ) throws -> ScaffoldOutcome {
            let pipeline = try Discover.collectVisibleSuggestions(
                directory: directory,
                explicitTestDirectory: testDirectory,
                diagnostics: diagnostics
            )
            let shapesByName = pipeline.typeShapesByName
            let resolver = GeneratorResolver(types: Array(shapesByName.values))

            var stubs: [String] = []
            var names: [String] = []
            for name in shapesByName.keys.sorted() {
                let shape = shapesByName[name]!
                // Only scaffold types that don't fully derive.
                guard case .todo = DerivationStrategist.strategy(
                    for: shape, resolve: resolver.customTypeGenerator
                ) else { continue }
                guard let stub = ScaffoldEmitter.stub(
                    for: shape, resolve: resolver.customTypeGenerator
                ) else { continue }
                stubs.append(stub)
                names.append(name)
            }
            guard !stubs.isEmpty else {
                return ScaffoldOutcome(fileText: nil, scaffoldedTypeNames: [])
            }
            return ScaffoldOutcome(
                fileText: wrap(stubs: stubs, typeCount: names.count),
                scaffoldedTypeNames: names
            )
        }

        static func defaultOutputURL(packageRoot: URL?) -> URL {
            (packageRoot ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                .appendingPathComponent("Tests/Generated/SwiftInfer/Scaffolds.generated.swift")
        }

        static func wrap(stubs: [String], typeCount: Int) -> String {
            """
            // SCAFFOLDED GENERATORS (swift-infer) — review, complete each <#...#>
            // placeholder, then move these into your test target (types must be in scope).
            //
            // \(typeCount) type(s) partially derived — the rest needs your domain knowledge.

            import PropertyLawKit
            import Foundation

            \(stubs.joined(separator: "\n\n"))
            """
        }
    }
}
