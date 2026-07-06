import Foundation
import SwiftInferCore

/// Productionizes the measured pipeline into a runnable verifier. Discovers
/// **both** value-semantics candidates (structs, copy-mutate-compare) and
/// defensive-copy candidates (classes with a `copy()`/`clone()`, Ch. 9 §9.3),
/// verifies each against its kit law, and returns a unified per-candidate
/// outcome.
///
/// Two reachability modes:
/// - **Self-contained (5a)** — `verify(...)`: package the target's sources
///   standalone + plain `import` (`public`, dependency-free targets).
/// - **Path-dependency (5b)** — `verifyInPackage(...)`: `.package(path:)` the
///   user's real package + `@testable import` (reaches `internal` types + real
///   dependencies; the build passes `-enable-testing`).
///
/// Serial by design: one verifier workdir is reused across candidates (only
/// `main.swift` changes), so the path-dep + kit graph builds cold once.
public enum ValueSemanticVerifier {

    /// 5a — self-contained: package the target's sources standalone.
    public static func verify(
        targetDirectory: URL,
        moduleName: String,
        workParent: URL
    ) throws -> [ValueSemanticVerifyResult] {
        let jobs = try jobs(in: targetDirectory, moduleName: moduleName, testable: false)
        guard !jobs.isEmpty else { return [] }
        let corpusRoot = try CorpusPackager.package(
            moduleName: moduleName,
            fromSourcesDirectory: targetDirectory,
            into: workParent
        )
        let manifest = selfContainedManifest(corpusRoot: corpusRoot, moduleName: moduleName)
        return try run(jobs, manifest: manifest, workParent: workParent)
    }

    /// 5b — path-dependency: verify the target module inside the user's real
    /// package (`packagePath`), reaching `internal` types via `@testable`.
    public static func verifyInPackage(
        packagePath: URL,
        targetDirectory: URL,
        moduleName: String,
        workParent: URL
    ) throws -> [ValueSemanticVerifyResult] {
        let jobs = try jobs(in: targetDirectory, moduleName: moduleName, testable: true)
        guard !jobs.isEmpty else { return [] }
        let manifest = pathDependencyManifest(packagePath: packagePath, moduleName: moduleName)
        return try run(jobs, manifest: manifest, workParent: workParent)
    }

    // MARK: - Jobs

    /// A unit of verification work — a pre-emitted stub, or a skip reason.
    private struct VerifyJob {
        let typeName: String
        let location: SourceLocation
        let stub: String?
        let notVerifiableReason: String?
    }

    /// Discover value-semantics (struct) + defensive-copy (class) candidates and
    /// turn each into a job (an emitted stub, or a not-verifiable reason).
    private static func jobs(
        in targetDirectory: URL,
        moduleName: String,
        testable: Bool
    ) throws -> [VerifyJob] {
        let valueSemantic = try ValueSemanticDiscoverer.discover(directory: targetDirectory)
            .map { valueSemanticJob($0, moduleName: moduleName, testable: testable) }
        let defensiveCopy = try DefensiveCopyDiscoverer.discover(directory: targetDirectory)
            .map { defensiveCopyJob($0, moduleName: moduleName, testable: testable) }
        return valueSemantic + defensiveCopy
    }

    private static func valueSemanticJob(
        _ candidate: ValueSemanticCandidate,
        moduleName: String,
        testable: Bool
    ) -> VerifyJob {
        let stub = ValueSemanticStubEmitter
            .inputs(for: candidate, moduleName: moduleName, testable: testable)
            .map(ValueSemanticStubEmitter.emit)
        let reason = candidate.equatability != .equatable
            ? "not Equatable (the copy-mutate-compare law compares instances with ==)"
            : "no payload-free mutation method to drive"
        return VerifyJob(
            typeName: candidate.typeName,
            location: candidate.location,
            stub: stub,
            notVerifiableReason: stub == nil ? reason : nil
        )
    }

    private static func defensiveCopyJob(
        _ candidate: DefensiveCopyCandidate,
        moduleName: String,
        testable: Bool
    ) -> VerifyJob {
        let stub = DefensiveCopyStubEmitter
            .inputs(for: candidate, moduleName: moduleName, testable: testable)
            .map(DefensiveCopyStubEmitter.emit)
        let reason = candidate.equatability != .equatable
            ? "not Equatable (the defensive-copy law compares instances with ==)"
            : "no payload-free mutation method to drive"
        return VerifyJob(
            typeName: candidate.typeName,
            location: candidate.location,
            stub: stub,
            notVerifiableReason: stub == nil ? reason : nil
        )
    }

    // MARK: - Shared verify loop

    private static func run(
        _ jobs: [VerifyJob],
        manifest: String,
        workParent: URL
    ) throws -> [ValueSemanticVerifyResult] {
        let workdir = workParent.appendingPathComponent("verifier")
        let sources = workdir.appendingPathComponent("Sources/SwiftInferVerifier")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try manifest.write(to: workdir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let mainFile = sources.appendingPathComponent("main.swift")
        return jobs.map { classify($0, workdir: workdir, mainFile: mainFile) }
    }

    private static func classify(_ job: VerifyJob, workdir: URL, mainFile: URL) -> ValueSemanticVerifyResult {
        guard let stub = job.stub else {
            return result(job, .notVerifiable(reason: job.notVerifiableReason ?? "not verify-ready"))
        }
        do {
            try stub.write(to: mainFile, atomically: true, encoding: .utf8)
            let build = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
            guard build.exitCode == 0 else {
                return result(job, .buildFailed(detail: excerpt(build.stderr)))
            }
            let outcome = VerifyResultParser.parse(try VerifierSubprocess.runVerifierBinary(workdir: workdir))
            return result(job, status(from: outcome))
        } catch {
            return result(job, .error(reason: "\(error)"))
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
        _ job: VerifyJob,
        _ status: ValueSemanticVerifyResult.Status
    ) -> ValueSemanticVerifyResult {
        ValueSemanticVerifyResult(typeName: job.typeName, location: job.location, status: status)
    }

    private static func excerpt(_ stderr: String) -> String {
        let lines = stderr.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return lines.suffix(3).joined(separator: " / ")
    }

    // MARK: - Verifier manifests

    static func selfContainedManifest(corpusRoot: URL, moduleName: String) -> String {
        manifest(packagePath: corpusRoot.path, packageIdentity: moduleName, moduleName: moduleName)
    }

    static func pathDependencyManifest(packagePath: URL, moduleName: String) -> String {
        manifest(packagePath: packagePath.path, packageIdentity: packagePath.lastPathComponent, moduleName: moduleName)
    }

    private static func manifest(packagePath: String, packageIdentity: String, moduleName: String) -> String {
        """
        // swift-tools-version: 6.1
        import PackageDescription
        let package = Package(
            name: "SwiftInferVerifier",
            platforms: [.macOS(.v14)],
            dependencies: [
                .package(path: "\(packagePath)"),
                .package(url: "https://github.com/x-sheep/swift-property-based.git", from: "1.0.0"),
                .package(url: "https://github.com/Joseph-Cursio/SwiftPropertyLaws.git", from: "3.5.0")
            ],
            targets: [
                .executableTarget(
                    name: "SwiftInferVerifier",
                    dependencies: [
                        .product(name: "\(moduleName)", package: "\(packageIdentity)"),
                        .product(name: "PropertyBased", package: "swift-property-based"),
                        .product(name: "PropertyLawKit", package: "SwiftPropertyLaws")
                    ]
                )
            ]
        )
        """
    }
}
