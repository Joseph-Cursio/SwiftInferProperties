import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("AssociativityTemplate — reducer/fold + vocabulary + vetoes")
struct AssociativityTemplateBehaviorTests {

    // MARK: - Reducer/fold usage signal (PRD §5.3, +20)

    @Test("Reducer-fold usage adds 20 when the candidate's name is in the corpus reducerOps set")
    func reducerOpsSignalFiresWhenNamePresent() throws {
        let summary = makeAssociativitySummary(
            name: "combine",
            returnType: "State",
            paramTypes: ("State", "State")
        )
        // 30 type + 40 curated `combine` + 20 reducer = 90 → Strong.
        let suggestion = try #require(
            AssociativityTemplate.suggest(for: summary, reducerOps: ["combine"])
        )
        #expect(suggestion.score.total == 90)
        #expect(suggestion.score.tier == .strong)
        let reducerLine = suggestion.explainability.whySuggested.first { line in
            line.contains("Reduce/fold usage")
        }
        #expect(reducerLine == "Reduce/fold usage detected in corpus: 'combine' referenced as a reducer op (+20)")
    }

    @Test("Reducer-fold usage by itself doesn't fire when the candidate isn't referenced")
    func reducerOpsSignalAbsentWhenNameMissing() throws {
        let summary = makeAssociativitySummary(
            name: "combine",
            returnType: "State",
            paramTypes: ("State", "State")
        )
        let suggestion = try #require(
            AssociativityTemplate.suggest(for: summary, reducerOps: ["something_else"])
        )
        // 30 + 40 = 70, no reducer bonus.
        #expect(suggestion.score.total == 70)
    }

    @Test("Reducer-fold usage on an unnamed type-only candidate promotes Possible to Likely")
    func reducerOpsSignalAlonePromotesPossibleToLikely() throws {
        // No name match — domain-specific name not in the curated/vocab
        // list. Type alone (30) is .possible (20..<40); add reducer (20)
        // and the total reaches 50 → .likely (40..<75 per PRD §4.2).
        let summary = makeAssociativitySummary(
            name: "fuse",
            returnType: "Frame",
            paramTypes: ("Frame", "Frame")
        )
        let suggestion = try #require(
            AssociativityTemplate.suggest(for: summary, reducerOps: ["fuse"])
        )
        #expect(suggestion.score.total == 50)
        #expect(suggestion.score.tier == .likely)
    }

    // MARK: - Project vocabulary (commutativity verbs reused)

    @Test("Project-vocabulary commutativity verb on (T, T) -> T scores 70 (Likely)")
    func projectVocabularyVerb() {
        let summary = makeAssociativitySummary(
            name: "unionGraphs",
            returnType: "Graph",
            paramTypes: ("Graph", "Graph")
        )
        let vocabulary = Vocabulary(commutativityVerbs: ["unionGraphs"])
        let suggestion = AssociativityTemplate.suggest(for: summary, vocabulary: vocabulary)
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
    }

    @Test("Curated verb wins over project-vocabulary when both list the same name")
    func curatedTakesPrecedenceOverProjectVocabulary() throws {
        let summary = makeAssociativitySummary(
            name: "merge",
            returnType: "Set",
            paramTypes: ("Set", "Set")
        )
        let vocabulary = Vocabulary(commutativityVerbs: ["merge"])
        let suggestion = try #require(AssociativityTemplate.suggest(for: summary, vocabulary: vocabulary))
        #expect(suggestion.score.total == 70)
        let nameLine = suggestion.explainability.whySuggested.first { line in
            line.contains("verb match")
        }
        #expect(nameLine == "Curated commutativity verb match: 'merge' (+40)")
    }

    @Test("Empty vocabulary leaves curated behaviour unchanged")
    func emptyVocabularyLeavesCuratedAlone() {
        let summary = makeAssociativitySummary(
            name: "merge",
            returnType: "Set",
            paramTypes: ("Set", "Set")
        )
        let suggestion = AssociativityTemplate.suggest(for: summary, vocabulary: .empty)
        #expect(suggestion?.score.total == 70)
    }

    // MARK: - Vetoes

    @Test("Non-deterministic body veto suppresses regardless of name signal")
    func nonDeterministicVetoSuppresses() {
        let summary = makeAssociativitySummary(
            name: "merge",
            returnType: "Set",
            paramTypes: ("Set", "Set"),
            bodySignals: BodySignals(
                hasNonDeterministicCall: true,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: ["Date"]
            )
        )
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }
}
