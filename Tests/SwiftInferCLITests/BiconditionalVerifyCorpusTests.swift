import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Cycle 137 — fast guard on the checked-in biconditional verify corpus
/// (`Tests/Fixtures/biconditional-verify-corpus/`): packaging + discovery
/// surfaces exactly the three intended biconditional identities, all at the
/// gated `.possible` baseline (no evidence yet). Discovery is AST-only, so
/// this is fast; the measured baseline that exercises the cycle-135/136
/// full-coverage pin-overrule on the *second* gated family is
/// `BiconditionalVerifyCorpusMeasuredTests`.
@Suite("Biconditional verify corpus — discovery coverage (cycle 137)")
struct BiconditionalVerifyCorpusTests {

    @Test("packaging + discovery surfaces exactly the five biconditional identities at .possible")
    func discoversTheCuratedIdentities() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("biconditional-verify-corpus-discovery")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "BiconditionalVerifyCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let suggestions = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
            target: "BiconditionalVerifyCorpus",
            workingDirectory: root
        )
        let biconditional = suggestions.filter { $0.family == .biconditional }
        let found = Set(biconditional.map { "\($0.reducerQualifiedName) \($0.predicate)" })

        let expected: Set<String> = [
            "SessionFeature.body state.isActive == (state.token != nil)",
            "ConnectionFeature.body state.isFetching == (state.payload != nil)",
            "StaleFeature.body state.isLoading == (state.data != nil)",
            // cycle 142 — literal-inferred Bool + inverse-drift false positive.
            "FeedFeature.body state.isRefreshing == (state.feed != nil)",
            "PendingFeature.body state.isFetchingMore == (state.nextPage != nil)"
        ]
        #expect(found == expected)

        // Gated baseline: every biconditional pick sits at .possible pre-verify.
        #expect(biconditional.allSatisfy { $0.tier == .possible })

        // The corpus surfaces no other family (one Bool-flag × one Optional
        // per reducer; no ≥2 presentation slots, no count/array, no
        // selected*/collection, no witness-vocab action names).
        #expect(suggestions.allSatisfy { $0.family == .biconditional })
    }

    /// `Tests/Fixtures/biconditional-verify-corpus/`, resolved against
    /// `#filePath` so it holds regardless of `swift test`'s cwd.
    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferCLITests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("biconditional-verify-corpus")
    }()
}
