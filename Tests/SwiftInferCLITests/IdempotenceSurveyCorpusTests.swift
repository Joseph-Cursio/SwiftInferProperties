import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Cycle 115 — fast guard on the checked-in verify-ready idempotence survey
/// corpus (`Tests/Fixtures/idempotence-survey-corpus/`): packaging it and
/// discovering over it surfaces exactly the intended idempotence identities
/// (the curated exact + prefix witness vocabulary, plus the one deliberate
/// `set*` false positive). Discovery is AST-only, so this is fast; the
/// measured-survey baseline is `IdempotenceSurveyCorpusMeasuredTests`.
@Suite("Idempotence survey corpus — discovery coverage (cycle 115)")
struct IdempotenceSurveyCorpusTests {

    @Test("packaging + discovery surfaces exactly the curated idempotence identities (13 across 4 carrier shapes)")
    func discoversTheCuratedIdentities() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("idempotence-survey-corpus-discovery")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "IdempotenceSurveyCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let suggestions = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
            target: "IdempotenceSurveyCorpus",
            workingDirectory: root
        )
        let idempotence = suggestions.filter { $0.family == .idempotence }
        let found = Set(idempotence.map { "\($0.reducerQualifiedName) \($0.predicate)" })

        let expected: Set<String> = [
            // cycle 115 — generic struct-method carriers
            "NavigationReducer.reduce .dismiss",
            "NavigationReducer.reduce .close",
            "NavigationReducer.reduce .hide",
            "SelectionReducer.reduce .select",
            "SelectionReducer.reduce .selectFirst",
            "SelectionReducer.reduce .showDetail",
            "SettingsReducer.reduce .cancel",
            "SettingsReducer.reduce .setBadge",
            // cycle 116 — TCA-convention witnesses (task/delegate/binding)
            "TCAFeatureReducer.reduce .task",
            "TCAFeatureReducer.reduce .delegate",
            "TCAFeatureReducer.reduce .binding",
            // cycle 116 — Elm-style free-function carrier, named `reduce`
            // (cycle-117 pin fix makes the bare free-function name resolvable)
            "reduce .refresh",
            // ReSwift-style free function `(Action, State?) -> State`
            // (the .reSwift carrier; reversed-arg verify emit)
            "reSwiftCounterReducer .reset"
        ]
        #expect(found == expected)

        // No-evidence baseline: every identity sits at .likely before any
        // measured run (the cycle-107 promotion; pre-survey).
        #expect(idempotence.allSatisfy { $0.tier == .likely })
    }

    /// `Tests/Fixtures/idempotence-survey-corpus/`, resolved against
    /// `#filePath` so it holds regardless of `swift test`'s cwd.
    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferCLITests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("idempotence-survey-corpus")
    }()
}
