import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// PROTOTYPE — end-to-end measured proof of DEPENDENCY-FAKING construction:
/// a view model that injects a `Store` protocol is NOT zero-arg
/// constructible, so the verifier synthesizes a no-op `Fake_Store` and
/// constructs `LibraryModel(store: Fake_Store())` before driving its
/// actions. This is the slice that reaches dependency-injected (real-app
/// shaped) view models.
///
///   - `selectAll` (idempotent) → bothPass — constructed via the fake
///   - `selectNext` (advances cursor) → defaultFails
///
/// Spawns real `swift build`s; tagged `.subprocess`.
@Suite("ViewModel faked-dependency verify — measured (prototype)", .tags(.subprocess))
struct ViewModelFakedDepVerifyMeasuredTests {

    @Test("a protocol-injected view model is constructed via a synthesized fake and verified")
    func measuredFakedDependencyConstruction() throws {
        let protocols = try ViewModelProtocolScanner.scan(directory: Self.corpusDirectory)
        #expect(protocols.contains { $0.name == "Store" && $0.isFakeable })

        let candidates = try ViewModelDiscoverer.discover(directory: Self.corpusDirectory)
        let library = try #require(candidates.first { $0.typeName == "LibraryModel" })

        // It is NOT zero-arg constructible (the injected `store`).
        #expect(library.constructibility == .requiresArguments(["store"]))
        // The dependency constructor synthesizes the fake + construction.
        let construction = try #require(ViewModelDependencyConstructor.resolve(library, protocols: protocols))
        #expect(construction.expression == "LibraryModel(store: Fake_Store())")
        #expect(construction.preamble.contains("struct Fake_Store: Store"))

        // Idempotence candidates that are sync + no-arg.
        let signatures = Set(
            ViewModelInteractionAnalyzer.analyze(library)
                .filter { $0.family == .idempotence }
                .compactMap(\.subjects.first)
        )
        let actions = library.actions
            .filter { signatures.contains($0.signature) && !$0.isAsync && $0.parameterTypes.isEmpty }
            .map(\.name)
            .sorted()
        #expect(actions == ["selectAll", "selectNext"])

        let workdir = try Self.makeWorkdir(corpus: Self.corpusDirectory)
        defer { try? FileManager.default.removeItem(at: workdir) }
        let verifierFile = workdir
            .appendingPathComponent("Sources/SwiftInferVerifier/main.swift")
        let fields = library.stateFields.map(\.name)

        var outcomes: [String: VerifyOutcome] = [:]
        for action in actions {
            let stub = ViewModelIdempotenceStubEmitter.emit(
                .init(
                    typeName: "LibraryModel",
                    actionName: action,
                    stateFieldNames: fields,
                    preamble: construction.preamble,
                    construction: construction.expression
                )
            )
            try stub.write(to: verifierFile, atomically: true, encoding: .utf8)
            let build = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
            guard build.exitCode == 0 else {
                Issue.record("build failed for \(action): \(build.stderr)")
                continue
            }
            outcomes[action] = VerifyResultParser.parse(try VerifierSubprocess.runVerifierBinary(workdir: workdir))
        }

        if case .bothPass = outcomes["selectAll"] {
            // Constructed LibraryModel(store: Fake_Store()); selectAll idempotent.
        } else {
            Issue.record("selectAll expected bothPass; got \(String(describing: outcomes["selectAll"]))")
        }
        if case .defaultFails = outcomes["selectNext"] {
            // selectNext advances the cursor.
        } else {
            Issue.record("selectNext expected defaultFails; got \(String(describing: outcomes["selectNext"]))")
        }
    }

    static let corpusDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("viewmodel-faked-dep-corpus")
    }()

    static func makeWorkdir(corpus: URL) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-faked-dep-\(UUID().uuidString)")
        let sources = root.appendingPathComponent("Sources/SwiftInferVerifier")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let manifest = """
        // swift-tools-version: 6.1
        import PackageDescription
        let package = Package(
            name: "SwiftInferVerifier",
            platforms: [.macOS(.v14)],
            targets: [.executableTarget(name: "SwiftInferVerifier")]
        )
        """
        try manifest.write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        let corpusFiles = try FileManager.default
            .contentsOfDirectory(at: corpus, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        for file in corpusFiles {
            try FileManager.default.copyItem(
                at: file,
                to: sources.appendingPathComponent(file.lastPathComponent)
            )
        }
        return root
    }
}
