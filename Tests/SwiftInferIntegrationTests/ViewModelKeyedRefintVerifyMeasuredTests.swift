import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// PROTOTYPE — end-to-end measured proof of KEYED referential-integrity
/// verification: a scalar-key selection (`selectedTrackID: Int?`) over a
/// collection of `Identifiable` elements (`[Track]`), referenced by `\.id`
/// — the common real-world shape (`selectedViolationId` over `[Violation]`).
/// Gated by the `IdentifiableResolver` (cycle-139 posture).
///
///   - `SafePlaylistModel` (selects an existing id) → bothPass
///   - `GhostPlaylistModel.selectGhost` (dangling id) → defaultFails
///
/// Spawns real `swift build`s; tagged `.subprocess`.
@Suite("ViewModel keyed refint verify — measured (prototype)", .tags(.subprocess))
struct ViewModelKeyedRefintVerifyMeasuredTests {

    @Test("keyed refint: valid-selection model bothPass, dangling-id model defaultFails")
    func measuredKeyedRefint() throws {
        // Identifiable evidence from the corpus type decls (Track has `id`).
        let scanned = try FunctionScanner.scanCorpus(directory: Self.corpusDirectory)
        let identifiable = IdentifiableResolver(typeDecls: scanned.typeDecls)
        #expect(identifiable.classify(typeText: "Track") == .identifiable)

        let candidates = try ViewModelDiscoverer.discover(directory: Self.corpusDirectory)
        let safe = try #require(candidates.first { $0.typeName == "SafePlaylistModel" })
        let ghost = try #require(candidates.first { $0.typeName == "GhostPlaylistModel" })

        // Value-membership alone gates the keyed form; the Identifiable
        // resolver unlocks it.
        #expect(ViewModelRefintResolver.resolve(safe) == nil)
        let keyed = try #require(ViewModelRefintResolver.resolve(safe, identifiable: identifiable))
        #expect(keyed.predicate.contains("$0.id == probe.selectedTrackID!"))

        let workdir = try Self.makeWorkdir(corpus: Self.corpusDirectory)
        defer { try? FileManager.default.removeItem(at: workdir) }
        let verifierFile = workdir
            .appendingPathComponent("Sources/SwiftInferVerifier/main.swift")

        func verify(_ candidate: ViewModelCandidate) throws -> VerifyOutcome {
            let resolved = try #require(
                ViewModelRefintResolver.resolve(candidate, identifiable: identifiable)
            )
            let stub = ViewModelInvariantStubEmitter.emit(Self.makeInputs(candidate, predicate: resolved.predicate))
            try stub.write(to: verifierFile, atomically: true, encoding: .utf8)
            let build = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
            guard build.exitCode == 0 else {
                Issue.record("build failed for \(candidate.typeName): \(build.stderr)")
                return .error(reason: "build failed")
            }
            return VerifyResultParser.parse(try VerifierSubprocess.runVerifierBinary(workdir: workdir))
        }

        if case .bothPass = try verify(safe) {
            // SafePlaylistModel only ever selects an existing track id.
        } else {
            Issue.record("SafePlaylistModel expected bothPass")
        }
        if case .defaultFails = try verify(ghost) {
            // selectGhost() sets a dangling id 999 → invariant violated.
        } else {
            Issue.record("GhostPlaylistModel expected defaultFails")
        }
    }

    static func makeInputs(
        _ candidate: ViewModelCandidate,
        predicate: String
    ) -> ViewModelInvariantStubEmitter.Inputs {
        var drivers: [ViewModelInvariantStubEmitter.Driver] = []
        for action in candidate.actions.sorted(by: { $0.name < $1.name })
        where action.parameterTypes.isEmpty {
            drivers.append(.init(name: action.name, label: nil, valuesExpression: nil))
        }
        return .init(typeName: candidate.typeName, predicate: predicate, drivers: drivers)
    }

    static let corpusDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("viewmodel-keyed-refint-corpus")
    }()

    static func makeWorkdir(corpus: URL) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-keyed-refint-\(UUID().uuidString)")
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
