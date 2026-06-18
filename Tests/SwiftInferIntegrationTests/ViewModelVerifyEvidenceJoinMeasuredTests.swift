import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// PROTOTYPE — the discover↔verify LOOP for MVVM, end to end: discover a
/// view model → surface its idempotence suggestions (at `.possible`) →
/// verify them → write `verify-evidence.json` keyed to each suggestion's
/// identity → re-fold via the production `InteractionVerifyEvidenceScoring`
/// → the verified invariant is **promoted past `.possible`** and the
/// disproven one is **suppressed**. Same join the reducer pipeline uses.
///
/// Spawns real `swift build`s; tagged `.subprocess`.
@Suite("ViewModel verify-evidence join — measured (prototype)", .tags(.subprocess))
struct ViewModelVerifyEvidenceJoinMeasuredTests {

    @Test("verified MVVM idempotence is promoted past Possible; disproven is suppressed")
    func measuredVerifyEvidenceJoin() throws {
        let candidates = try ViewModelDiscoverer.discover(directory: Self.corpusDirectory)
        let model = try #require(candidates.first { $0.typeName == "SelectionModel" })
        let suggestions = ViewModelInteractionAnalyzer.suggestions(
            for: model,
            firstSeenAt: Date(timeIntervalSince1970: 0)
        )
        // Both start at Possible (a new inference source).
        #expect(suggestions.allSatisfy { $0.tier == .possible })
        let selectAll = try #require(suggestions.first {
            $0.family == .idempotence && $0.predicate.contains("'selectAll'")
        })
        let selectNext = try #require(suggestions.first {
            $0.family == .idempotence && $0.predicate.contains("'selectNext'")
        })

        // Package root for the evidence store — needs a Package.swift so the
        // store's `findPackageRoot` anchors here (so repeated records
        // accumulate into one `.swiftinfer/verify-evidence.json`).
        let packageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-join-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: packageRoot) }
        try "// swift-tools-version: 6.1\nimport PackageDescription\nlet package = Package(name: \"P\")"
            .write(to: packageRoot.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        // Verify each, then record evidence keyed to the suggestion identity.
        let workdir = try Self.makeWorkdir()
        defer { try? FileManager.default.removeItem(at: workdir) }
        ViewModelVerifyEvidence.record(
            for: selectAll,
            outcome: try Self.verify(action: "selectAll", fields: model.stateFields.map(\.name), workdir: workdir),
            packageRoot: packageRoot
        )
        ViewModelVerifyEvidence.record(
            for: selectNext,
            outcome: try Self.verify(action: "selectNext", fields: model.stateFields.map(\.name), workdir: workdir),
            packageRoot: packageRoot
        )

        // Re-fold through the production discover-side consumer.
        let evidence = VerifyEvidenceStore.load(startingFrom: packageRoot).log.records
        let byIdentity = Dictionary(evidence.map { ($0.identityHash, $0) }) { _, latest in latest }
        let graded = InteractionVerifyEvidenceScoring.applied(to: suggestions, evidenceByIdentity: byIdentity)

        let gradedSelectAll = try #require(graded.first { $0.identity == selectAll.identity })
        let gradedSelectNext = try #require(graded.first { $0.identity == selectNext.identity })
        // bothPass promotes idempotence past Possible (→ verified);
        // defaultFails suppresses.
        #expect(gradedSelectAll.tier == .verified)
        #expect(gradedSelectNext.tier == .suppressed)
    }

    /// Emit + build + run an idempotence verifier for one no-arg action.
    static func verify(action: String, fields: [String], workdir: URL) throws -> VerifyOutcome {
        let stub = ViewModelIdempotenceStubEmitter.emit(
            .init(typeName: "SelectionModel", actionName: action, stateFieldNames: fields)
        )
        try stub.write(
            to: workdir.appendingPathComponent("Sources/SwiftInferVerifier/main.swift"),
            atomically: true,
            encoding: .utf8
        )
        let build = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
        guard build.exitCode == 0 else {
            Issue.record("build failed for \(action): \(build.stderr)")
            return .error(reason: "build failed")
        }
        return VerifyResultParser.parse(try VerifierSubprocess.runVerifierBinary(workdir: workdir))
    }

    static let corpusDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("viewmodel-verify-corpus")
    }()

    static func makeWorkdir() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-join-wd-\(UUID().uuidString)")
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
        for file in try FileManager.default
            .contentsOfDirectory(at: corpusDirectory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "swift" }) {
            try FileManager.default.copyItem(
                at: file,
                to: sources.appendingPathComponent(file.lastPathComponent)
            )
        }
        return root
    }
}
