import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Cycle 136 — fast guard on the checked-in cardinality verify corpus
/// (`Tests/Fixtures/cardinality-verify-corpus/`): packaging + discovery
/// surfaces exactly the three intended cardinality identities, all at the
/// gated `.possible` baseline (no evidence yet). Discovery is AST-only, so
/// this is fast; the measured baseline that exercises the cycle-135
/// full-coverage pin-overrule is `CardinalityVerifyCorpusMeasuredTests`.
@Suite("Cardinality verify corpus — discovery coverage (cycle 136)")
struct CardinalityVerifyCorpusTests {

    @Test("packaging + discovery surfaces exactly the three cardinality identities at .possible")
    func discoversTheCuratedIdentities() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("cardinality-verify-corpus-discovery")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "CardinalityVerifyCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let suggestions = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
            target: "CardinalityVerifyCorpus",
            workingDirectory: root
        )
        let cardinality = suggestions.filter { $0.family == .cardinality }

        // Exactly one cardinality witness per reducer (two presentation Bool
        // flags each).
        #expect(Set(cardinality.map(\.reducerQualifiedName)) == [
            "RouterFeature.body", "DrawerFeature.body", "LeakyFeature.body"
        ])
        // Gated baseline: every cardinality pick sits at .possible pre-verify.
        #expect(cardinality.allSatisfy { $0.tier == .possible })
        // Each predicate is the `Σ indicators <= 1` shape over its two flags.
        #expect(cardinality.allSatisfy { $0.predicate.hasSuffix("<= 1") })
        let byReducer = Dictionary(uniqueKeysWithValues: cardinality.map {
            ($0.reducerQualifiedName, $0.predicate)
        })
        #expect(byReducer["RouterFeature.body"]?.contains("state.isShowingSheet") == true)
        #expect(byReducer["RouterFeature.body"]?.contains("state.isPresentingAlert") == true)
        #expect(byReducer["DrawerFeature.body"]?.contains("state.isPresentingPopover") == true)
        #expect(byReducer["LeakyFeature.body"]?.contains("state.isPresentingToast") == true)

        // The corpus surfaces no other family (no Optional / witness-vocab
        // action names), so cardinality is the whole story.
        #expect(suggestions.allSatisfy { $0.family == .cardinality })
    }

    /// `Tests/Fixtures/cardinality-verify-corpus/`, resolved against
    /// `#filePath` so it holds regardless of `swift test`'s cwd.
    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferCLITests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("cardinality-verify-corpus")
    }()
}
