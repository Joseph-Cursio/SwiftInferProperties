import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// PROTOTYPE — end-to-end measured proof that a view model living in its
/// OWN SwiftPM module is verified via a package PATH-DEPENDENCY: the corpus
/// is packaged (`CorpusPackager`), and the verifier's `Package.swift`
/// declares `.package(path:)` on it + `import`s the module — so the view
/// model + its `Store` protocol come from a real compiled package, not
/// inlined source. This is the productionization route for verifying an
/// app's own packaged ViewModels (the MVVM analog of the algebraic
/// `--corpus-module` path-dep). A synthesized `Fake_Store` (conforming to
/// the imported public protocol) satisfies the injected dependency.
///
///   - `selectAll` (idempotent) → bothPass
///   - `selectNext` (advances cursor) → defaultFails
///
/// Spawns real `swift build`s resolving the path-dependency; tagged `.subprocess`.
@Suite("ViewModel package path-dependency verify — measured (prototype)", .tags(.subprocess))
struct ViewModelPackageVerifyMeasuredTests {

    @Test("a view model in a path-dependency package is constructed + verified across the module boundary")
    func measuredPackagePathDependency() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-package-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        // 1. Package the corpus into its own SwiftPM module.
        let corpusRoot = try CorpusPackager.package(
            moduleName: "LibraryCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        // 2. Discover + resolve construction off the corpus SOURCE (AST).
        let candidates = try ViewModelDiscoverer.discover(directory: Self.fixtureDirectory)
        let library = try #require(candidates.first { $0.typeName == "LibraryModel" })
        let protocols = try ViewModelProtocolScanner.scan(directory: Self.fixtureDirectory)
        let construction = try #require(ViewModelDependencyConstructor.resolve(library, protocols: protocols))
        #expect(construction.expression == "LibraryModel(store: Fake_Store())")

        // 3. Build a verifier package that PATH-DEPENDS on the corpus.
        let workdir = parent.appendingPathComponent("verifier")
        let sources = workdir.appendingPathComponent("Sources/SwiftInferVerifier")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Self.verifierManifest(corpusRoot: corpusRoot).write(
            to: workdir.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        let outcomes = try Self.verify(
            actions: ["selectAll", "selectNext"],
            construction: construction,
            stateFields: library.stateFields.map(\.name),
            workdir: workdir,
            mainFile: sources.appendingPathComponent("main.swift")
        )

        if case .bothPass = outcomes["selectAll"] {
            // Constructed LibraryModel(store: Fake_Store()) across the module boundary.
        } else {
            Issue.record("selectAll expected bothPass; got \(String(describing: outcomes["selectAll"]))")
        }
        if case .defaultFails = outcomes["selectNext"] {
            // selectNext advances the cursor.
        } else {
            Issue.record("selectNext expected defaultFails; got \(String(describing: outcomes["selectNext"]))")
        }
    }

    /// Emit + build + run an idempotence verifier per action against the
    /// path-dependency package (`extraImports: ["LibraryCorpus"]`).
    static func verify(
        actions: [String],
        construction: ViewModelDependencyConstructor.Construction,
        stateFields: [String],
        workdir: URL,
        mainFile: URL
    ) throws -> [String: VerifyOutcome] {
        var outcomes: [String: VerifyOutcome] = [:]
        for action in actions {
            let stub = ViewModelIdempotenceStubEmitter.emit(
                .init(
                    typeName: "LibraryModel",
                    actionName: action,
                    stateFieldNames: stateFields,
                    preamble: construction.preamble,
                    construction: construction.expression,
                    extraImports: ["LibraryCorpus"]
                )
            )
            try stub.write(to: mainFile, atomically: true, encoding: .utf8)
            let build = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
            guard build.exitCode == 0 else {
                Issue.record("build failed for \(action): \(build.stderr)")
                continue
            }
            outcomes[action] = VerifyResultParser.parse(try VerifierSubprocess.runVerifierBinary(workdir: workdir))
        }
        return outcomes
    }

    static func verifierManifest(corpusRoot: URL) -> String {
        """
        // swift-tools-version: 6.1
        import PackageDescription
        let package = Package(
            name: "SwiftInferVerifier",
            platforms: [.macOS(.v14)],
            dependencies: [.package(path: \"\(corpusRoot.path)\")],
            targets: [
                .executableTarget(
                    name: "SwiftInferVerifier",
                    dependencies: [.product(name: "LibraryCorpus", package: "LibraryCorpus")]
                )
            ]
        )
        """
    }

    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("viewmodel-package-corpus")
    }()
}
