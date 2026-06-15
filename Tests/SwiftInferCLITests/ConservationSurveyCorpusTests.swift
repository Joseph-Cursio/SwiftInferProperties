import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Cycle 134 — fast guard on the checked-in verify-ready *conservation*
/// survey corpus (`Tests/Fixtures/conservation-survey-corpus/`): packaging
/// it and discovering over it surfaces exactly the two intended
/// conservation identities (the count-shaped aggregate × array witness),
/// one genuinely-conserving and one deliberate false positive. Discovery
/// is AST-only, so this is fast; the measured-survey baseline (and the
/// `.possible → .verified` promotion proof) is
/// `ConservationSurveyCorpusMeasuredTests`.
///
/// This is the second interaction family wired to a measured-verify path
/// after idempotence — and the first *un-gated* one demonstrated
/// end-to-end (the measured-verify mechanism was already family-generic;
/// cycle 134 proves it on conservation, the cleanest non-idempotence
/// shape: a State-only predicate, no Finding-G gate, no `Identifiable`
/// friction).
@Suite("Conservation survey corpus — discovery coverage (cycle 134)")
struct ConservationSurveyCorpusTests {

    @Test("packaging + discovery surfaces exactly the four curated conservation identities at .possible")
    func discoversTheCuratedIdentities() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("conservation-survey-corpus-discovery")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "ConservationSurveyCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let suggestions = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
            target: "ConservationSurveyCorpus",
            workingDirectory: root
        )
        let conservation = suggestions.filter { $0.family == .conservation }
        let found = Set(conservation.map { "\($0.reducerQualifiedName) \($0.predicate)" })

        let expected: Set<String> = [
            "InventoryReducer.reduce state.count == state.items.count",
            "BadgeReducer.reduce state.badgeCount == state.notifications.count",
            // cycle 140 — widened: a recompute-style true positive and a
            // clear-without-reset false positive.
            "CartReducer.reduce state.itemCount == state.lineItems.count",
            "RosterReducer.reduce state.memberCount == state.members.count"
        ]
        #expect(found == expected)

        // No-evidence baseline: conservation sits at .possible before any
        // measured run (initialScore 30, un-gated; pre-survey).
        #expect(conservation.allSatisfy { $0.tier == .possible })
    }

    /// `Tests/Fixtures/conservation-survey-corpus/`, resolved against
    /// `#filePath` so it holds regardless of `swift test`'s cwd.
    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferCLITests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("conservation-survey-corpus")
    }()
}
