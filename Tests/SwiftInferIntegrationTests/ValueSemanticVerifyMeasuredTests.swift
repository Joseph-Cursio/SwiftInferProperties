import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// PROTOTYPE — slice 3 end-to-end measured proof for the ValueSemantic feature.
/// Discovers value-semantics candidates off a real corpus, packages it into its
/// own SwiftPM module (`CorpusPackager`), then builds — per candidate — a
/// verifier that PATH-DEPENDS on the corpus + `PropertyLawKit` (kit v3.4.0),
/// retroactively conforms the imported struct to `ValueSemantic`, and runs the
/// kit's copy-mutate-compare law:
///
///   - `SafeStore` (correct copy-on-write) → bothPass — no false positive.
///   - `LeakyStore` (shared reference, non-`mutating` leak) → defaultFails —
///     the kit surfaces the minimal leaking mutation script.
///   - `ClosureCounter` (stored closure capturing a heap `var`) → defaultFails,
///     caught only by the kit v3.5.0 multi-step interleaving law.
///
/// Spawns real `swift build`s resolving the path-dependency + the kit; tagged
/// `.subprocess` (runs under `make batch*`, skipped by `make test-fast`).
@Suite("ValueSemantic verify corpus — measured (slice 3)", .tags(.subprocess))
struct ValueSemanticVerifyMeasuredTests {

    @Test("correct-CoW verifies bothPass; a shared-reference leak defaultFails, across a packaged module")
    func measuredValueSemanticVerify() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("vs-verify-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        // 1. Discover candidates off the fixture SOURCE (AST) — the discover→verify link.
        let candidates = try ValueSemanticDiscoverer.discover(directory: Self.fixtureDirectory)
        #expect(candidates.contains { $0.typeName == "SafeStore" })
        #expect(candidates.contains { $0.typeName == "LeakyStore" })
        #expect(candidates.contains { $0.typeName == "ClosureCounter" })

        // 2. Package the corpus into its own dependency-free module.
        let corpusRoot = try CorpusPackager.package(
            moduleName: "ValueSemanticCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        // 3. Build a verifier that path-depends on the corpus + kit.
        let workdir = parent.appendingPathComponent("verifier")
        let sources = workdir.appendingPathComponent("Sources/SwiftInferVerifier")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Self.verifierManifest(corpusRoot: corpusRoot).write(
            to: workdir.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let outcomes = try Self.verify(candidates: candidates, workdir: workdir, sources: sources)

        if case .bothPass = outcomes["SafeStore"] {
            // Correct CoW: mutation on a copy clones storage; original untouched.
        } else {
            Issue.record("SafeStore expected bothPass; got \(String(describing: outcomes["SafeStore"]))")
        }
        if case .defaultFails = outcomes["LeakyStore"] {
            // Shared reference: the copy's append leaks into the original.
        } else {
            Issue.record("LeakyStore expected defaultFails; got \(String(describing: outcomes["LeakyStore"]))")
        }
        if case .defaultFails = outcomes["ClosureCounter"] {
            // Closure capture: caught only by the multi-step interleaving law.
        } else {
            Issue.record("ClosureCounter expected defaultFails; got \(String(describing: outcomes["ClosureCounter"]))")
        }
    }

    /// Emit + build + run a verifier per verify-ready candidate, keyed by type
    /// name. Non-verify-ready candidates (gated by the emitter) are skipped.
    static func verify(
        candidates: [ValueSemanticCandidate],
        workdir: URL,
        sources: URL
    ) throws -> [String: VerifyOutcome] {
        var outcomes: [String: VerifyOutcome] = [:]
        for candidate in candidates.sorted(by: { $0.typeName < $1.typeName }) {
            guard let inputs = ValueSemanticStubEmitter.inputs(
                for: candidate,
                moduleName: "ValueSemanticCorpus"
            ) else { continue }
            try ValueSemanticStubEmitter.emit(inputs).write(
                to: sources.appendingPathComponent("main.swift"),
                atomically: true,
                encoding: .utf8
            )
            let build = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
            guard build.exitCode == 0 else {
                Issue.record("build failed for \(candidate.typeName): \(build.stderr)")
                continue
            }
            outcomes[candidate.typeName] = VerifyResultParser.parse(
                try VerifierSubprocess.runVerifierBinary(workdir: workdir)
            )
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
            dependencies: [
                .package(path: "\(corpusRoot.path)"),
                .package(url: "https://github.com/x-sheep/swift-property-based.git", from: "1.0.0"),
                .package(url: "https://github.com/Joseph-Cursio/SwiftPropertyLaws.git", from: "3.5.0")
            ],
            targets: [
                .executableTarget(
                    name: "SwiftInferVerifier",
                    dependencies: [
                        .product(name: "ValueSemanticCorpus", package: "ValueSemanticCorpus"),
                        .product(name: "PropertyBased", package: "swift-property-based"),
                        .product(name: "PropertyLawKit", package: "SwiftPropertyLaws")
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
            .appendingPathComponent("valuesemantic-verify-corpus")
    }()
}
