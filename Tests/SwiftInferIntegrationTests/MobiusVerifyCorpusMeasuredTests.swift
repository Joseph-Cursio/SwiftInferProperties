import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// The verify-ready REAL-Mobius corpus survey. Packages
/// `Tests/Fixtures/mobius-verify-corpus/` (a `(Model, Event) -> Next<Model,
/// Effect>` update — the `.mobius` carrier) and runs the measured `--all`
/// survey through the `.interactionMobius` verify path: the corpus is
/// co-compiled into the verifier target, MobiusCore is declared as a package
/// dependency (pinned to an unreleased `master` revision — the tagged
/// releases don't build under the current Swift toolchain), and the new model
/// is extracted from `Next.model` with effects discarded.
///
/// Spawns a real `swift build` resolving Spotify's Mobius.swift; tagged
/// `.subprocess`. Splits two idempotence witnesses: `reset` (zero model →
/// bothPass) and `refresh` (exact-witness name but the body increments → the
/// deliberate false positive → measured-defaultFails, disproven by execution).
@Suite("Mobius verify-ready corpus — measured survey", .tags(.subprocess))
struct MobiusVerifyCorpusMeasuredTests {

    @Test("real Mobius update verifies idempotence end-to-end via the Next.model extraction")
    func surveysRealMobiusCorpus() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("mobius-verify-corpus")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "MobiusVerifyCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let summary = try await VerifyInteractionSurvey.run(
            target: "MobiusVerifyCorpus",
            familyFilter: "idempotence",
            sequenceCount: 128,
            workingDirectory: root
        )
        #expect(summary.contains("Identities: 2 (--family idempotence)"))
        #expect(summary.contains("1 measured-bothPass"))
        #expect(summary.contains("1 measured-defaultFails"))
        // The true witness verifies through the Next.model extraction; the
        // name-vs-behavior false positive is disproven by execution.
        #expect(summary.contains("[measured-bothPass]") && summary.contains(".reset"))
        #expect(summary.contains("[measured-defaultFails]") && summary.contains(".refresh"))

        let stored = VerifyEvidenceStore.load(startingFrom: root)
        #expect(stored.log.records.count == 2)
        #expect(stored.log.records.filter { $0.outcome == .measuredBothPass }.count == 1)
        #expect(stored.log.records.filter { $0.outcome == .measuredDefaultFails }.count == 1)

        // Payoff: discover reads the evidence — the survivor renders Verified
        // (AST-only); the false positive is suppressed.
        let discovered = try SwiftInferCommand.DiscoverInteraction.runPipeline(
            target: "MobiusVerifyCorpus",
            includePossible: true,
            workingDirectory: root
        )
        #expect(discovered.contains("(Verified)"))
        #expect(!discovered.contains(".refresh"))
    }

    /// `Tests/Fixtures/mobius-verify-corpus/`, resolved against `#filePath`.
    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("mobius-verify-corpus")
    }()
}
