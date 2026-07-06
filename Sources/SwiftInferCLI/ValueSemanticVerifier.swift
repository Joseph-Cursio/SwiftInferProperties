import Foundation
import SwiftInferCore

/// Productionizes the slice-3/4 measured pipeline: discover value-semantics
/// candidates in a target, verify each against the kit's copy-mutate-compare
/// law, and return a per-candidate outcome.
///
/// **Slice 5a — self-contained mode.** The target's sources are packaged as a
/// standalone module (`CorpusPackager`) and the verifier path-depends on it.
/// This works when the target is self-contained + its types are `public`; a
/// target with external dependencies or `internal` types surfaces as
/// `.buildFailed`. Slice 5b adds a path-dependency + `@testable import` mode
/// (spiked) that reaches real `internal` types.
///
/// Serial by design: one verifier workdir is reused across candidates (only
/// `main.swift` changes), so a warm `.build/` gives incremental rebuilds
/// instead of N cold ones.
public enum ValueSemanticVerifier {

    /// Verify every value-semantics candidate discovered in `targetDirectory`.
    /// Results are returned in discovery order; the renderer sorts + groups.
    public static func verify(
        targetDirectory: URL,
        moduleName: String,
        workParent: URL
    ) throws -> [ValueSemanticVerifyResult] {
        let candidates = try ValueSemanticDiscoverer.discover(directory: targetDirectory)
        guard !candidates.isEmpty else { return [] }

        let corpusRoot = try CorpusPackager.package(
            moduleName: moduleName,
            fromSourcesDirectory: targetDirectory,
            into: workParent
        )
        let workdir = workParent.appendingPathComponent("verifier")
        let sources = workdir.appendingPathComponent("Sources/SwiftInferVerifier")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try verifierManifest(corpusRoot: corpusRoot, moduleName: moduleName).write(
            to: workdir.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        let mainFile = sources.appendingPathComponent("main.swift")

        return candidates.map { candidate in
            classify(candidate, moduleName: moduleName, workdir: workdir, mainFile: mainFile)
        }
    }

    // MARK: - Per-candidate

    private static func classify(
        _ candidate: ValueSemanticCandidate,
        moduleName: String,
        workdir: URL,
        mainFile: URL
    ) -> ValueSemanticVerifyResult {
        guard let inputs = ValueSemanticStubEmitter.inputs(for: candidate, moduleName: moduleName) else {
            let reason = candidate.equatability != .equatable
                ? "not Equatable (the copy-mutate-compare law compares instances with ==)"
                : "no payload-free mutation method to drive"
            return result(candidate, .notVerifiable(reason: reason))
        }
        do {
            try ValueSemanticStubEmitter.emit(inputs).write(to: mainFile, atomically: true, encoding: .utf8)
            let build = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
            guard build.exitCode == 0 else {
                return result(candidate, .buildFailed(detail: excerpt(build.stderr)))
            }
            let outcome = VerifyResultParser.parse(try VerifierSubprocess.runVerifierBinary(workdir: workdir))
            return result(candidate, status(from: outcome))
        } catch {
            return result(candidate, .error(reason: "\(error)"))
        }
    }

    private static func status(from outcome: VerifyOutcome) -> ValueSemanticVerifyResult.Status {
        switch outcome {
        case .bothPass, .edgeCaseAdvisory:
            return .verifiedSafe

        case .defaultFails(let detail):
            return .confirmedLeak(repro: detail.input)

        case .error(let reason):
            return .error(reason: reason)
        }
    }

    private static func result(
        _ candidate: ValueSemanticCandidate,
        _ status: ValueSemanticVerifyResult.Status
    ) -> ValueSemanticVerifyResult {
        ValueSemanticVerifyResult(
            typeName: candidate.typeName,
            location: candidate.location,
            status: status
        )
    }

    /// Last few non-empty stderr lines — enough to see the compile error
    /// without dumping the whole build log into the report.
    private static func excerpt(_ stderr: String) -> String {
        let lines = stderr.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return lines.suffix(3).joined(separator: " / ")
    }

    // MARK: - Verifier package

    static func verifierManifest(corpusRoot: URL, moduleName: String) -> String {
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
                        .product(name: "\(moduleName)", package: "\(moduleName)"),
                        .product(name: "PropertyBased", package: "swift-property-based"),
                        .product(name: "PropertyLawKit", package: "SwiftPropertyLaws")
                    ]
                )
            ]
        )
        """
    }
}
