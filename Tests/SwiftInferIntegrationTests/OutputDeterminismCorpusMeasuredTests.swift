import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Slice B2 — end-to-end measured proof of `outputDeterminism` for convention
/// roles (VIPER/MVP). The corpus is packaged into its own SwiftPM module; per
/// role a verifier is emitted (a `RecordingFakeEmitter` fake for the output
/// collaborator + the presenter constructed across the module boundary), built
/// via a path-dependency, and run twice — the recorded output logs are compared.
///
///   - `SafePresenter.greet` — output is a pure function of fresh state → the two
///     runs' logs match → bothPass → Verified.
///   - `LeakyPresenter.refresh` — output embeds `UUID()` → the logs differ →
///     defaultFails → suppressed. (A no-op fake could never catch this; the
///     recording fake is what gives the check teeth.)
///
/// Spawns real `swift build`s resolving the path-dependency; tagged `.subprocess`.
@Suite("Output-determinism corpus — VIPER/MVP recording-fake measured baseline", .tags(.subprocess))
struct OutputDeterminismCorpusMeasuredTests {

    @Test("deterministic output passes; a UUID()-based output fails — 1 bothPass + 1 defaultFails")
    func outputDeterminismSplits() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("output-determinism-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        // 1. Package the corpus into its own SwiftPM module.
        let corpusRoot = try CorpusPackager.package(
            moduleName: "OutputDeterminismCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        // 2. Discover the roles + protocols off the corpus source (AST).
        let roles = try ConventionRoleDiscoverer.discover(directory: Self.fixtureDirectory)
        let protocols = try ViewModelProtocolScanner.scan(directory: Self.fixtureDirectory)
        let safe = try #require(roles.first { $0.typeName == "SafePresenter" })
        let leaky = try #require(roles.first { $0.typeName == "LeakyPresenter" })

        // 3. Build a verifier package that PATH-DEPENDS on the corpus.
        let workdir = parent.appendingPathComponent("verifier")
        let sources = workdir.appendingPathComponent("Sources/SwiftInferVerifier")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Self.verifierManifest(corpusRoot: corpusRoot).write(
            to: workdir.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        let mainFile = sources.appendingPathComponent("main.swift")

        let safeOutcome = try Self.verify(
            role: safe, protocols: protocols, workdir: workdir, mainFile: mainFile
        )
        let leakyOutcome = try Self.verify(
            role: leaky, protocols: protocols, workdir: workdir, mainFile: mainFile
        )

        if case .bothPass = safeOutcome {
            // SafePresenter's output is deterministic across the two runs.
        } else {
            Issue.record("SafePresenter expected bothPass; got \(String(describing: safeOutcome))")
        }
        if case .defaultFails = leakyOutcome {
            // LeakyPresenter's UUID()-based output differs between runs.
        } else {
            Issue.record("LeakyPresenter expected defaultFails; got \(String(describing: leakyOutcome))")
        }
    }

    /// Emit the output-determinism verifier for `role`, build it against the
    /// path-dependency package, run it, and parse the outcome.
    static func verify(
        role: StatefulRole,
        protocols: [ViewModelProtocolScanner.ProtocolDecl],
        workdir: URL,
        mainFile: URL
    ) throws -> VerifyOutcome {
        let output = try #require(outputProtocol(for: role, protocols: protocols))
        let source = try #require(
            OutputDeterminismVerifierEmitter.emit(
                role: role,
                outputProtocol: output,
                dependencyProtocols: protocols,
                moduleName: "OutputDeterminismCorpus"
            )
        )
        try source.write(to: mainFile, atomically: true, encoding: .utf8)
        let build = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
        guard build.exitCode == 0 else {
            Issue.record("build failed for \(role.typeName): \(build.stderr)")
            return .error(reason: "build failed")
        }
        return VerifyResultParser.parse(try VerifierSubprocess.runVerifierBinary(workdir: workdir))
    }

    /// The `ProtocolDecl` of the role's assertable output collaborator.
    static func outputProtocol(
        for role: StatefulRole,
        protocols: [ViewModelProtocolScanner.ProtocolDecl]
    ) -> ViewModelProtocolScanner.ProtocolDecl? {
        let outputCollaborator = role.collaborators.first { collaborator in
            if case .output = collaborator.role { return true }
            return false
        }
        guard let outputCollaborator else { return nil }
        var bare = outputCollaborator.protocolType.trimmingCharacters(in: .whitespaces)
        if bare.hasPrefix("any ") { bare = String(bare.dropFirst(4)) }
        bare = bare.trimmingCharacters(in: CharacterSet(charactersIn: "?! "))
        return protocols.first { $0.name == bare }
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
                    dependencies: [
                        .product(name: "OutputDeterminismCorpus", package: "OutputDeterminismCorpus")
                    ]
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
            .appendingPathComponent("output-determinism-corpus")
    }()
}
