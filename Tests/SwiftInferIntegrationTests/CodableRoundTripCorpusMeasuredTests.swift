import Foundation
@testable import SwiftInferCLI
import Testing

/// End-to-end measured proof of the codable-round-trip verify path. Emits a
/// `CodableRoundTripStubEmitter` JSON round-trip verifier per corpus type,
/// co-compiles it with the `codable-roundtrip-corpus` in a minimal
/// (dependency-free) SwiftPM package, runs it, and asserts the outcome:
///
///   - `Temperature` (faithful custom codec) → bothPass
///   - `ScaledRatio` (encode scales ×100, decode ÷1000 — the swift-asn1
///     `decode(encode(128)) == -128` class of scale bug) → defaultFails
///
/// Both read as ordinary custom `Codable` conformances; only execution through a
/// real `JSONEncoder` / `JSONDecoder` tells them apart. Spawns real
/// `swift build`s; tagged `.subprocess`.
@Suite("Codable-round-trip verify corpus — measured (JSON decode(encode(x)) == x)", .tags(.subprocess))
struct CodableRoundTripCorpusMeasuredTests {

    struct VerifyCase: Sendable {
        let carrier: String
        let valueExpression: String
        let expectBothPass: Bool
    }

    static let cases: [VerifyCase] = [
        VerifyCase(
            carrier: "Temperature",
            valueExpression: "Temperature(celsius: Double(Int(rng.next() % 400)) - 200)",
            expectBothPass: true
        ),
        VerifyCase(
            carrier: "ScaledRatio",
            valueExpression: "ScaledRatio(value: Double(Int(rng.next() % 100)))",
            expectBothPass: false
        )
    ]

    @Test("each corpus codec verifies to its expected round-trip outcome")
    func measuredCodableRoundTrip() throws {
        let workdir = try Self.makeWorkdir(corpus: Self.corpusDirectory)
        defer { try? FileManager.default.removeItem(at: workdir) }
        let verifierFile = workdir
            .appendingPathComponent("Sources/SwiftInferVerifier/main.swift")

        var outcomes: [String: VerifyOutcome] = [:]
        for verifyCase in Self.cases {
            let stub = CodableRoundTripStubEmitter.emit(
                .init(carrierType: verifyCase.carrier, valueExpression: verifyCase.valueExpression)
            )
            try stub.write(to: verifierFile, atomically: true, encoding: .utf8)
            let build = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
            guard build.exitCode == 0 else {
                Issue.record("build failed for \(verifyCase.carrier): \(build.stderr)")
                continue
            }
            let run = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
            outcomes[verifyCase.carrier] = VerifyResultParser.parse(run)
        }

        for verifyCase in Self.cases {
            let outcome = outcomes[verifyCase.carrier]
            if verifyCase.expectBothPass {
                if case .bothPass = outcome { continue }
                Issue.record("\(verifyCase.carrier) expected bothPass; got \(String(describing: outcome))")
            } else {
                if case .defaultFails = outcome { continue }
                Issue.record("\(verifyCase.carrier) expected defaultFails; got \(String(describing: outcome))")
            }
        }
    }

    // MARK: - Fixtures + workdir

    static let corpusDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("codable-roundtrip-corpus")
    }()

    /// Stage a minimal, dependency-free SwiftPM package with the corpus
    /// co-compiled into the `SwiftInferVerifier` executable target.
    static func makeWorkdir(corpus: URL) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cbt-verify-\(UUID().uuidString)")
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
