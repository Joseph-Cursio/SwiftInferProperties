import Foundation
@testable import SwiftInferCLI
import Testing

/// End-to-end measured proof of the reorder-partition verify path. Emits a
/// `ReorderPartitionStubEmitter` verifier per corpus method, co-compiles it with
/// the `reorder-partition-corpus` in a minimal (dependency-free) SwiftPM
/// package, runs it, and asserts the outcome:
///
///   - `stablePartitionWhole` (correct stable) → bothPass
///   - `buggyDropWhole` (drops an element — not a permutation) → defaultFails
///   - `unstablePartitionWhole` (correct, non-stable) → bothPass (non-stable check)
///   - `stablePartitionSubrange` (correct, fenced) → bothPass
///   - `buggyFenceSubrange` (reorders the whole array — the `0dba0e5` bug) → defaultFails
///
/// Only execution tells them apart — every name reads like a partition. Spawns
/// real `swift build`s; tagged `.subprocess`.
@Suite("Reorder-partition verify corpus — measured (split + permutation + fence)", .tags(.subprocess))
struct ReorderPartitionCorpusMeasuredTests {

    struct VerifyCase: Sendable {
        let method: String
        let hasSubrange: Bool
        let isStable: Bool
        let expectBothPass: Bool
    }

    static let cases: [VerifyCase] = [
        VerifyCase(method: "stablePartitionWhole", hasSubrange: false, isStable: true, expectBothPass: true),
        VerifyCase(method: "buggyDropWhole", hasSubrange: false, isStable: true, expectBothPass: false),
        VerifyCase(method: "unstablePartitionWhole", hasSubrange: false, isStable: false, expectBothPass: true),
        VerifyCase(method: "stablePartitionSubrange", hasSubrange: true, isStable: true, expectBothPass: true),
        VerifyCase(method: "buggyFenceSubrange", hasSubrange: true, isStable: true, expectBothPass: false)
    ]

    @Test("each corpus partition verifies to its expected split/permutation/fence outcome")
    func measuredReorderPartition() throws {
        let workdir = try Self.makeWorkdir(corpus: Self.corpusDirectory)
        defer { try? FileManager.default.removeItem(at: workdir) }
        let verifierFile = workdir
            .appendingPathComponent("Sources/SwiftInferVerifier/main.swift")

        var outcomes: [String: VerifyOutcome] = [:]
        for verifyCase in Self.cases {
            let stub = ReorderPartitionStubEmitter.emit(
                .init(
                    methodName: verifyCase.method,
                    hasSubrange: verifyCase.hasSubrange,
                    isStable: verifyCase.isStable
                )
            )
            try stub.write(to: verifierFile, atomically: true, encoding: .utf8)
            let build = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
            guard build.exitCode == 0 else {
                Issue.record("build failed for \(verifyCase.method): \(build.stderr)")
                continue
            }
            let run = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
            outcomes[verifyCase.method] = VerifyResultParser.parse(run)
        }

        for verifyCase in Self.cases {
            let outcome = outcomes[verifyCase.method]
            if verifyCase.expectBothPass {
                expectBothPass(outcome, verifyCase.method)
            } else {
                expectDefaultFails(outcome, verifyCase.method)
            }
        }
    }

    private func expectBothPass(_ outcome: VerifyOutcome?, _ label: String) {
        if case .bothPass = outcome { return }
        Issue.record("\(label) expected bothPass; got \(String(describing: outcome))")
    }

    private func expectDefaultFails(_ outcome: VerifyOutcome?, _ label: String) {
        if case .defaultFails = outcome { return }
        Issue.record("\(label) expected defaultFails; got \(String(describing: outcome))")
    }

    // MARK: - Fixtures + workdir

    static let corpusDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("reorder-partition-corpus")
    }()

    /// Stage a minimal, dependency-free SwiftPM package with the corpus
    /// co-compiled into the `SwiftInferVerifier` executable target.
    static func makeWorkdir(corpus: URL) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rp-verify-\(UUID().uuidString)")
        let sources = root.appendingPathComponent("Sources/SwiftInferVerifier")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let packageManifest = """
        // swift-tools-version: 6.1
        import PackageDescription
        let package = Package(
            name: "SwiftInferVerifier",
            platforms: [.macOS(.v14)],
            targets: [.executableTarget(name: "SwiftInferVerifier")]
        )
        """
        try packageManifest.write(
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
