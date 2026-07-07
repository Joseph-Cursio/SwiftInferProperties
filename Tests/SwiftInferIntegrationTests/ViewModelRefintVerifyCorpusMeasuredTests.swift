import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// PROTOTYPE — end-to-end measured proof of ViewModel referential-integrity
/// verification. Recognises the `viewmodel-refint-corpus` models, resolves
/// the value-membership invariant (`selected ⊆ items`), drives the action
/// alphabet, and checks the invariant after every step:
///
///   - `SafeCatalogModel` (guards membership) → bothPass
///   - `CatalogModel.toggle` (inserts an arbitrary id) → defaultFails
///
/// Spawns real `swift build`s; tagged `.subprocess`.
@Suite("ViewModel refint verify corpus — measured (prototype)", .tags(.subprocess))
struct ViewModelRefintVerifyCorpusMeasuredTests {

    @Test("invariant-maintaining model bothPass, invariant-breaking model defaultFails")
    func measuredViewModelRefint() throws {
        let candidates = try ViewModelDiscoverer.discover(directory: Self.corpusDirectory)
        let safe = try #require(candidates.first { $0.typeName == "SafeCatalogModel" })
        let buggy = try #require(candidates.first { $0.typeName == "CatalogModel" })

        let workdir = try Self.makeWorkdir(corpus: Self.corpusDirectory)
        defer { try? FileManager.default.removeItem(at: workdir) }
        let verifierFile = workdir
            .appendingPathComponent("Sources/SwiftInferVerifier/main.swift")

        func verify(_ candidate: ViewModelCandidate) throws -> VerifyOutcome {
            let resolved = try #require(
                ViewModelRefintResolver.resolve(candidate),
                "expected a verifiable refint pairing on \(candidate.typeName)"
            )
            let stub = ViewModelInvariantStubEmitter.emit(Self.makeInputs(candidate, resolved: resolved))
            try stub.write(to: verifierFile, atomically: true, encoding: .utf8)
            let build = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
            guard build.exitCode == 0 else {
                Issue.record("build failed for \(candidate.typeName): \(build.stderr)")
                return .error(reason: "build failed")
            }
            return VerifyResultParser.parse(try VerifierSubprocess.runVerifierBinary(workdir: workdir))
        }

        if case .bothPass = try verify(safe) {
            // SafeCatalogModel guards membership → invariant maintained.
        } else {
            Issue.record("SafeCatalogModel expected bothPass")
        }
        if case .defaultFails = try verify(buggy) {
            // CatalogModel.toggle(0) drives `selected` out of `items`.
        } else {
            Issue.record("CatalogModel expected defaultFails")
        }

        // Payoff: an ORDER-DEPENDENT bug the old single-pass (sorted: drop, pick)
        // PASSED, now caught because randomized sequences reach `pick` before `drop`.
        let orderBug = try #require(candidates.first { $0.typeName == "OrderBugModel" })
        if case .defaultFails = try verify(orderBug) {
            // pick()-then-drop() leaves `selected` dangling over empty `items`.
        } else {
            Issue.record("OrderBugModel expected defaultFails (interleaving bug missed by single-pass)")
        }
    }

    /// Drive every no-arg / single-arg-generatable action; disclose the rest.
    static func makeInputs(
        _ candidate: ViewModelCandidate,
        resolved: ViewModelRefintResolver.Resolved
    ) -> ViewModelInvariantStubEmitter.Inputs {
        var drivers: [ViewModelInvariantStubEmitter.Driver] = []
        var excluded: [String] = []
        for action in candidate.actions.sorted(by: { $0.name < $1.name }) {
            switch action.parameterTypes.count {
            case 0:
                drivers.append(.init(name: action.name, label: nil, valuesExpression: nil))

            case 1:
                if let values = ViewModelArgumentGenerator
                    .candidateValuesExpression(for: action.parameterTypes[0]) {
                    drivers.append(.init(
                        name: action.name,
                        label: action.firstParameterLabel,
                        valuesExpression: values
                    ))
                } else {
                    excluded.append(action.name)
                }

            default:
                excluded.append(action.name)
            }
        }
        return .init(
            typeName: candidate.typeName,
            predicate: resolved.predicate,
            drivers: drivers,
            excludedActions: excluded
        )
    }

    // MARK: - Fixtures + workdir

    static let corpusDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("viewmodel-refint-corpus")
    }()

    static func makeWorkdir(corpus: URL) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-refint-\(UUID().uuidString)")
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
