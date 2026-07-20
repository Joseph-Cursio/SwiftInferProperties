import Foundation
@testable import SwiftInferCLI
import Testing

/// End-to-end measured proof of the init-decode codec verify path. Emits an
/// `InitDecodeStubEmitter` verifier per corpus codec, co-compiles it with the
/// `init-decode-corpus` in a minimal (dependency-free) SwiftPM package, runs it,
/// and asserts the outcome:
///
///   - `HexCode` (correct hex codec) → bothPass
///   - `LossyCode` (encode drops the sign) → defaultFails (mismatch)
///   - `StrictCode` (failable init rejects its own encoder's output) → defaultFails (decode-nil)
///
/// Only execution tells them apart — every one reads like a codec. Spawns real
/// `swift build`s; tagged `.subprocess`.
@Suite("Init-decode verify corpus — measured codec round-trip", .tags(.subprocess))
struct InitDecodeCorpusMeasuredTests {

    struct VerifyCase: Sendable {
        let typeName: String
        let encodeMethod: String
        let decodeLabel: String
        let expectBothPass: Bool
    }

    static let cases: [VerifyCase] = [
        VerifyCase(typeName: "HexCode", encodeMethod: "hex", decodeLabel: "hex", expectBothPass: true),
        VerifyCase(typeName: "LossyCode", encodeMethod: "encoded", decodeLabel: "encoded", expectBothPass: false),
        VerifyCase(
            typeName: "StrictCode", encodeMethod: "serialized",
            decodeLabel: "serialized", expectBothPass: false
        )
    ]

    @Test("each corpus codec verifies its init-decode round-trip to the expected outcome")
    func measuredInitDecode() throws {
        let workdir = try Self.makeWorkdir(corpus: Self.corpusDirectory)
        defer { try? FileManager.default.removeItem(at: workdir) }
        let verifierFile = workdir
            .appendingPathComponent("Sources/SwiftInferVerifier/main.swift")

        var outcomes: [String: VerifyOutcome] = [:]
        for verifyCase in Self.cases {
            let values = "[-255, -42, -1, 0, 1, 42, 255].map { \(verifyCase.typeName)(raw: $0) }"
            let stub = InitDecodeStubEmitter.emit(
                .init(
                    typeName: verifyCase.typeName,
                    encodeMethod: verifyCase.encodeMethod,
                    decodeLabel: verifyCase.decodeLabel,
                    isFailable: true,
                    valuesExpression: values
                )
            )
            try stub.write(to: verifierFile, atomically: true, encoding: .utf8)
            let build = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
            guard build.exitCode == 0 else {
                Issue.record("build failed for \(verifyCase.typeName): \(build.stderr)")
                continue
            }
            let run = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
            outcomes[verifyCase.typeName] = VerifyResultParser.parse(run)
        }

        for verifyCase in Self.cases {
            let outcome = outcomes[verifyCase.typeName]
            if verifyCase.expectBothPass {
                expectBothPass(outcome, verifyCase.typeName)
            } else {
                expectDefaultFails(outcome, verifyCase.typeName)
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
            .appendingPathComponent("init-decode-corpus")
    }()

    /// Stage a minimal, dependency-free SwiftPM package with the corpus
    /// co-compiled into the `SwiftInferVerifier` executable target.
    static func makeWorkdir(corpus: URL) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("id-verify-\(UUID().uuidString)")
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
