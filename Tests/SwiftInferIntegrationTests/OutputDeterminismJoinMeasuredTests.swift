import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// Slice B3b — the discover↔verify LOOP for convention roles, end to end:
/// discover a VIPER/MVP role → surface its `outputDeterminism` suggestion (at
/// `.possible`) → verify it with the recording-fake harness → write
/// `verify-evidence.json` keyed to the suggestion's identity → re-fold via the
/// production `InteractionVerifyEvidenceScoring` → the deterministic role is
/// **promoted past `.possible`** (→ `.verified`) and the nondeterministic one is
/// **suppressed**. The same join the reducer / MVVM pipelines use.
///
/// Spawns real `swift build`s resolving the corpus path-dependency; `.subprocess`.
@Suite("Output-determinism verify-evidence join — measured (prototype)", .tags(.subprocess))
struct OutputDeterminismJoinMeasuredTests {

    @Test("verified outputDeterminism is promoted past Possible; disproven is suppressed")
    func measuredVerifyEvidenceJoin() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-join-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        // Discover roles + protocols, map to suggestions (both at Possible).
        let roles = try ConventionRoleDiscoverer.discover(directory: Self.corpusDirectory)
        let protocols = try ViewModelProtocolScanner.scan(directory: Self.corpusDirectory)
        let suggestions = roles.flatMap {
            ConventionRoleInteractionAnalyzer.suggestions(for: $0, firstSeenAt: Date(timeIntervalSince1970: 0))
        }
        #expect(suggestions.allSatisfy { $0.tier == .possible })

        let env = try Self.makeEnvironment(parent: parent)
        for role in roles {
            let suggestion = try #require(suggestions.first { $0.reducerQualifiedName == role.typeName })
            let outcome = try OutputDeterminismVerify.verify(
                role: role,
                protocols: protocols,
                moduleName: "OutputDeterminismCorpus",
                workdir: env.workdir,
                mainFile: env.mainFile
            )
            OutputDeterminismVerifyEvidence.record(
                for: suggestion, outcome: outcome, packageRoot: env.packageRoot
            )
        }

        // Re-fold through the production discover-side consumer.
        let evidence = VerifyEvidenceStore.load(startingFrom: env.packageRoot).log.records
        #expect(evidence.count == 2)
        let byIdentity = Dictionary(evidence.map { ($0.identityHash, $0) }) { _, latest in latest }
        let graded = InteractionVerifyEvidenceScoring.applied(to: suggestions, evidenceByIdentity: byIdentity)

        let gradedSafe = try #require(graded.first { $0.reducerQualifiedName == "SafePresenter" })
        let gradedLeaky = try #require(graded.first { $0.reducerQualifiedName == "LeakyPresenter" })
        #expect(gradedSafe.tier == .verified)     // deterministic output → promoted
        #expect(gradedLeaky.tier == .suppressed)  // UUID() output → suppressed
    }

    private struct Environment {
        let workdir: URL
        let mainFile: URL
        let packageRoot: URL
    }

    /// Package the corpus, a path-dependency verifier workdir, and a
    /// Package.swift-anchored project root for the evidence store.
    private static func makeEnvironment(parent: URL) throws -> Environment {
        let corpusRoot = try CorpusPackager.package(
            moduleName: "OutputDeterminismCorpus",
            fromSourcesDirectory: corpusDirectory,
            into: parent
        )
        let workdir = parent.appendingPathComponent("verifier")
        let sources = workdir.appendingPathComponent("Sources/SwiftInferVerifier")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try verifierManifest(corpusRoot: corpusRoot).write(
            to: workdir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
        )
        let packageRoot = parent.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        try "// swift-tools-version: 6.1\nimport PackageDescription\nlet package = Package(name: \"P\")"
            .write(to: packageRoot.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        return Environment(
            workdir: workdir,
            mainFile: sources.appendingPathComponent("main.swift"),
            packageRoot: packageRoot
        )
    }

    private static func verifierManifest(corpusRoot: URL) -> String {
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
                    dependencies: [
                        .product(name: "OutputDeterminismCorpus", package: "OutputDeterminismCorpus")
                    ]
                )
            ]
        )
        """
    }

    static let corpusDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("output-determinism-corpus")
    }()
}
