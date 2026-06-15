import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Cycle 138 — the measured baseline for referential integrity, the FIFTH
/// and final interaction family to get a measured-verify path. Refint is
/// un-gated (no swiftProjectLintDeferral), so — like conservation — a
/// `bothPass` promotes through the normal path (30 + 50 = 80 → .strong →
/// .verified) with no pin-overrule. The one wrinkle is the predicate's
/// `$0.id` term: the curated element types are `Identifiable`, so the
/// generated stub compiles directly (no Identifiable gate needed for the
/// demonstration).
///
/// Over `Tests/Fixtures/refint-verify-corpus/` (two real `@Reducer`s), runs
/// `verify-interaction --all --family referential-integrity` and asserts:
///
///   - **LibraryFeature** — keeps `selectedBookID` pointing at an existing
///     book (or nil) → `measured-bothPass` → discover promotes it
///     `.possible → .verified` (no overrule disclosure — un-gated).
///   - **CatalogFeature** — `removeFirst` drops an item without fixing the
///     selection (the false positive) → `measured-defaultFails` →
///     suppressed.
///
/// Spawns real `swift build`s resolving swift-composable-architecture;
/// tagged `.subprocess`.
@Suite("Referential-integrity verify corpus — measured baseline (cycle 138)", .tags(.subprocess))
struct RefIntVerifyCorpusMeasuredTests {

    @Test("valid reducer verifies (→ Verified, un-gated); the dangling-selection false positive is suppressed")
    func measuredBaselineSplitsAndPromotes() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("refint-verify-corpus-measured")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "RefIntVerifyCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let summary = try await VerifyInteractionSurvey.run(
            target: "RefIntVerifyCorpus",
            familyFilter: "referential-integrity",
            sequenceCount: 128,
            workingDirectory: root
        )

        #expect(summary.contains("Identities: 2 (--family referential-integrity)"))
        #expect(summary.contains("1 measured-bothPass"))
        #expect(summary.contains("1 measured-defaultFails"))

        let stored = VerifyEvidenceStore.load(startingFrom: root)
        #expect(stored.log.records.count == 2)
        #expect(stored.log.records.filter { $0.outcome == .measuredBothPass }.count == 1)
        #expect(stored.log.records.filter { $0.outcome == .measuredDefaultFails }.count == 1)

        // Payoff: discover folds the evidence — Library promoted to Verified
        // through the ungated path (no overrule disclosure); Catalog
        // suppressed.
        let discovered = try SwiftInferCommand.DiscoverInteraction.runPipeline(
            target: "RefIntVerifyCorpus",
            includePossible: true,
            workingDirectory: root
        )
        #expect(discovered.contains("(Verified)"))
        #expect(discovered.contains("state.books.contains"))        // Library survives
        #expect(!discovered.contains("state.items.contains"))       // Catalog suppressed
        #expect(!discovered.contains("overruled"))                  // un-gated: no pin-overrule
        #expect(!discovered.contains("(Possible)"))                 // survivor promoted off .possible
    }

    /// `Tests/Fixtures/refint-verify-corpus/`, resolved against `#filePath`
    /// (this target can't see the CLI-test locator).
    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("refint-verify-corpus")
    }()
}
