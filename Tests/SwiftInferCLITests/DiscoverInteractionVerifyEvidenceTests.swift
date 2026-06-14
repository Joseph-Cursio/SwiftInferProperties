import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
import Testing

/// Cycle 112 — end-to-end proof of the verify-evidence *consumer* on the
/// `discover-interaction` render path: a real `.swiftinfer/verify-evidence.json`
/// (written exactly as `verify-interaction` writes it) is loaded, folded,
/// and reflected in the rendered suggestion stream. The fold logic itself
/// is unit-tested in `InteractionVerifyEvidenceScoringTests`; this proves
/// the load → fold → render wiring.
@Suite("discover-interaction verify-evidence consumer (cycle 112)")
struct DiscoverInteractionVerifyEvidenceTests {

    private typealias Command = SwiftInferCommand.DiscoverInteraction

    private let firstSeenAt = ISO8601DateFormatter().date(from: "2026-05-15T10:00:00Z")!

    /// The cycle-107 `.likely` idempotence fixture (single `.refresh`
    /// identity reducer) — surfaces one idempotence suggestion at
    /// `Score: 40 (Likely)` with no evidence.
    private static let idempotenceSource = """
    struct Inbox {
        struct State {
            var count: Int
            var items: [String]
        }
        enum Action { case refresh }
        static func reduce(_ s: State, _ a: Action) -> State { return s }
    }
    """

    @Test("bothPass evidence promotes the .likely idempotence pick to Verified in the rendered stream")
    func bothPassPromotesToVerified() throws {
        let directory = try makeFixturePackage(name: "VEConsumerBothPass")
        defer { try? FileManager.default.removeItem(at: directory) }

        // Discover the idempotence pick first so we key evidence on its
        // real identity (no guessing the predicate).
        let idem = try idempotencePick(in: directory)
        recordBothPass(for: idem, packageRoot: directory)

        let rendered = try Command.runPipeline(
            target: "MyApp",
            workingDirectory: directory,
            firstSeenAt: firstSeenAt
        )
        #expect(rendered.contains("Family:    idempotence"))
        // 40 (base) + 50 (bothPass) = 90 → strong → verified.
        #expect(rendered.contains("Score:     90 (Verified)"))
        #expect(rendered.contains("bothPass"))
    }

    @Test("defaultFails evidence suppresses the idempotence pick — it drops out of the stream")
    func defaultFailsSuppresses() throws {
        let directory = try makeFixturePackage(name: "VEConsumerDefaultFails")
        defer { try? FileManager.default.removeItem(at: directory) }

        let idem = try idempotencePick(in: directory)
        record(
            outcome: .measuredDefaultFails,
            detail: "at sequence index 2",
            for: idem,
            packageRoot: directory
        )

        // Even with --include-possible, a .suppressed pick is never shown.
        let rendered = try Command.runPipeline(
            target: "MyApp",
            includePossible: true,
            workingDirectory: directory,
            firstSeenAt: firstSeenAt
        )
        #expect(!rendered.contains("Family:    idempotence"))
    }

    @Test("with no evidence file the pick renders at its base .likely tier (consumer is a no-op)")
    func noEvidenceLeavesBaseTier() throws {
        let directory = try makeFixturePackage(name: "VEConsumerNoEvidence")
        defer { try? FileManager.default.removeItem(at: directory) }

        let rendered = try Command.runPipeline(
            target: "MyApp",
            workingDirectory: directory,
            firstSeenAt: firstSeenAt
        )
        #expect(rendered.contains("Family:    idempotence"))
        #expect(rendered.contains("Score:     40 (Likely)"))
    }

    // MARK: - Helpers

    private func idempotencePick(in directory: URL) throws -> InteractionInvariantSuggestion {
        let suggestions = try Command.collectSuggestions(
            target: "MyApp",
            workingDirectory: directory,
            firstSeenAt: firstSeenAt
        )
        return try #require(suggestions.first { $0.family == .idempotence })
    }

    private func recordBothPass(for suggestion: InteractionInvariantSuggestion, packageRoot: URL) {
        record(
            outcome: .measuredBothPass,
            detail: "totalRuns=1024 clean=1024",
            for: suggestion,
            packageRoot: packageRoot
        )
    }

    private func record(
        outcome: VerifyEvidenceOutcome,
        detail: String?,
        for suggestion: InteractionInvariantSuggestion,
        packageRoot: URL
    ) {
        _ = VerifyEvidenceRecorder.record(
            VerifyEvidence(
                identityHash: suggestion.identity.normalized,
                template: suggestion.family.rawValue,
                outcome: outcome,
                detail: detail,
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                swiftInferVersion: "1.118.0"
            ),
            packageRoot: packageRoot
        )
    }

    /// A fixture *package* (with a Package.swift root, so `VerifyEvidenceStore`
    /// resolves the package root and finds the evidence file) holding the
    /// idempotence reducer under `Sources/MyApp/`.
    private func makeFixturePackage(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiscoverInteractionVE-\(name)-\(UUID().uuidString)")
        let sources = base.appendingPathComponent("Sources").appendingPathComponent("MyApp")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: base.appendingPathComponent("Package.swift"))
        try Data(Self.idempotenceSource.utf8)
            .write(to: sources.appendingPathComponent("Inbox.swift"))
        return base
    }
}
