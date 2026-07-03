import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Phase 2 (Redux) — the first measured baseline for the determinism
/// family, the 6th interaction invariant. Determinism is unlike the five
/// witness-based families: it applies to every `.redux` reducer
/// unconditionally, and its stub is a per-step *two-call* comparison
/// (`reduce(s, a) == reduce(s, a)`) rather than a State-shape predicate.
///
/// The campaign thesis, on determinism: promotion gated on *execution*,
/// with execution catching a nondeterminism bug the static purity analyzer
/// provably cannot see. Over `Tests/Fixtures/determinism-verify-corpus/`:
///   - `PureCounterReducer` is a pure function → `reduce(s, a)` twice is
///     equal → `measured-bothPass` → `discover-interaction` promotes it
///     `.possible → .verified` (30 + 50 = 80 → `.strong` → promoted);
///   - `NondeterministicTagReducer` stamps each result with `Int.random`.
///     Static purity analysis labels it `.pure` (it inspects for TCA
///     effects / Task / hidden mutation, never `Int.random`), yet two
///     applications differ → `measured-defaultFails` → suppressed.
///
/// Real `swift build` + runs — tagged `.subprocess`.
@Suite("Determinism verify corpus — measured baseline (Phase 2 Redux)", .tags(.subprocess))
struct DeterminismVerifyCorpusMeasuredTests {

    @Test("survey records 1 bothPass + 1 defaultFails; discover promotes only the pure reducer")
    func measuredBaselineSplitsAndPromotes() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("determinism-verify-corpus-measured")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "DeterminismVerifyCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let summary = try await VerifyInteractionSurvey.run(
            target: "DeterminismVerifyCorpus",
            familyFilter: "determinism",
            sequenceCount: 128,
            workingDirectory: root
        )
        #expect(summary.contains("Identities: 2 (--family determinism)"))
        #expect(summary.contains("1 measured-bothPass"))
        #expect(summary.contains("1 measured-defaultFails"))

        // Evidence harvested for both determinism identities.
        let evidence = VerifyEvidenceStore.load(startingFrom: root).log.records
        #expect(evidence.count == 2)
        #expect(evidence.filter { $0.outcome == .measuredBothPass }.count == 1)
        #expect(evidence.filter { $0.outcome == .measuredDefaultFails }.count == 1)

        // Payoff: discover reads the evidence — the pure reducer is promoted
        // .possible → .verified; the random-tag reducer is suppressed
        // (defaultFails) and hidden from the stream even with the flag.
        let discovered = try SwiftInferCommand.DiscoverInteraction.runPipeline(
            target: "DeterminismVerifyCorpus",
            includePossible: true,
            workingDirectory: root
        )
        // Both determinism suggestions carry the same fixed predicate, so
        // distinguish by reducer name within each sentinel-delimited block.
        let blocks = discovered.components(separatedBy: "[Interaction-Invariant Suggestion]")
        func determinismBlock(reducer: String) -> String? {
            blocks.first {
                $0.contains("Family:    determinism") && $0.contains(reducer)
            }
        }
        #expect(determinismBlock(reducer: "PureCounterReducer")?.contains("(Verified)") == true)
        #expect(determinismBlock(reducer: "NondeterministicTagReducer") == nil)
    }

    /// `Tests/Fixtures/determinism-verify-corpus/`, resolved against
    /// `#filePath` (this target can't see the CLI-test locator).
    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("determinism-verify-corpus")
    }()
}
