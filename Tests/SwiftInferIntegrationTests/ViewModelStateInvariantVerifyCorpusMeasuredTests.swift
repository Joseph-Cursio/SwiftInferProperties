import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// PROTOTYPE — end-to-end measured proof of the three remaining
/// state-invariant families (cardinality / biconditional / conservation),
/// each via the shared drive-and-check harness. Per model: resolve the
/// family predicate, drive the action alphabet, re-check after every step.
///
///   - cardinality: `RouterModel` (mutex) bothPass / `LeakyRouterModel` defaultFails
///   - biconditional: `SessionModel` (in sync) bothPass / `DriftModel` defaultFails
///   - conservation: `CartModel` (recompute) bothPass / `BadgeModel` defaultFails
///
/// Spawns real `swift build`s; tagged `.subprocess`.
@Suite("ViewModel state-invariant verify corpus — measured (prototype)", .tags(.subprocess))
struct VMStateInvariantVerifyMeasuredTests {

    private struct InvariantCase {
        let typeName: String
        let resolve: (ViewModelCandidate) -> String?
        let expectBothPass: Bool
    }

    @Test("cardinality / biconditional / conservation — maintainers bothPass, breakers defaultFails")
    func measuredStateInvariants() throws {
        let cases: [InvariantCase] = [
            .init(typeName: "RouterModel", resolve: ViewModelCardinalityResolver.resolve, expectBothPass: true),
            .init(typeName: "LeakyRouterModel", resolve: ViewModelCardinalityResolver.resolve, expectBothPass: false),
            .init(typeName: "SessionModel", resolve: ViewModelBiconditionalResolver.resolve, expectBothPass: true),
            .init(typeName: "DriftModel", resolve: ViewModelBiconditionalResolver.resolve, expectBothPass: false),
            .init(typeName: "CartModel", resolve: ViewModelConservationResolver.resolve, expectBothPass: true),
            .init(typeName: "BadgeModel", resolve: ViewModelConservationResolver.resolve, expectBothPass: false)
        ]
        let candidates = try ViewModelDiscoverer.discover(directory: Self.corpusDirectory)
        let byName = Dictionary(uniqueKeysWithValues: candidates.map { ($0.typeName, $0) })

        let workdir = try Self.makeWorkdir(corpus: Self.corpusDirectory)
        defer { try? FileManager.default.removeItem(at: workdir) }
        let verifierFile = workdir
            .appendingPathComponent("Sources/SwiftInferVerifier/main.swift")

        for testCase in cases {
            let candidate = try #require(byName[testCase.typeName])
            let predicate = try #require(
                testCase.resolve(candidate),
                "no predicate resolved for \(testCase.typeName)"
            )
            let stub = ViewModelInvariantStubEmitter.emit(
                Self.makeInputs(candidate, predicate: predicate)
            )
            try stub.write(to: verifierFile, atomically: true, encoding: .utf8)
            let build = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
            guard build.exitCode == 0 else {
                Issue.record("build failed for \(testCase.typeName): \(build.stderr)")
                continue
            }
            let outcome = VerifyResultParser.parse(try VerifierSubprocess.runVerifierBinary(workdir: workdir))
            let isBothPass: Bool
            if case .bothPass = outcome { isBothPass = true } else { isBothPass = false }
            let want = testCase.expectBothPass ? "bothPass" : "defaultFails"
            #expect(
                isBothPass == testCase.expectBothPass,
                "\(testCase.typeName): expected \(want), got \(outcome)"
            )
        }
    }

    static func makeInputs(
        _ candidate: ViewModelCandidate,
        predicate: String
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
            predicate: predicate,
            drivers: drivers,
            excludedActions: excluded
        )
    }

    static let corpusDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("viewmodel-invariant-corpus")
    }()

    static func makeWorkdir(corpus: URL) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-invariant-\(UUID().uuidString)")
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
