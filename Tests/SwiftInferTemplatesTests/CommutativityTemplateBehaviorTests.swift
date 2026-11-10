import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("CommutativityTemplate — anti-commutativity, vocabulary, vetoes")
struct CommutativityTemplateBehaviorTests {

    // MARK: - Anti-commutativity counter-signal

    @Test("Curated anti-commutativity verb collapses score to suppressed")
    func antiCommutativitySuppresses() {
        let summary = makeCommutativitySummary(
            name: "concatenate",
            returnType: "Array",
            paramTypes: ("Array", "Array")
        )
        // 30 type-symmetry + (-30) anti-commutativity = 0 → suppressed.
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Curated anti-commutativity for `subtract` suppresses")
    func subtractAntiCommutativitySuppresses() {
        let summary = makeCommutativitySummary(
            name: "subtract",
            returnType: "Vector",
            paramTypes: ("Vector", "Vector")
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Project-vocabulary anti-commutativity verb suppresses too")
    func projectVocabAntiCommutativitySuppresses() {
        let summary = makeCommutativitySummary(
            name: "concatenateOrdered",
            returnType: "Array",
            paramTypes: ("Array", "Array")
        )
        let vocabulary = Vocabulary(antiCommutativityVerbs: ["concatenateOrdered"])
        #expect(CommutativityTemplate.suggest(for: summary, vocabulary: vocabulary) == nil)
    }

    @Test("Anti-commutativity counter-signal renders with the project-vocab detail line")
    func projectVocabAntiCommutativityDetailLineIfVisible() throws {
        // Pathological scenario where the score doesn't collapse: type-symmetry (+30)
        // plus a project-vocab COMMUTATIVITY verb (+40) plus a curated
        // anti-commutativity (-30) on a function whose name happens to
        // be in the project's commutativity list. Net: 40, Possible.
        let summary = makeCommutativitySummary(
            name: "subtract",
            returnType: "T",
            paramTypes: ("T", "T")
        )
        let vocabulary = Vocabulary(commutativityVerbs: ["subtract"])
        let suggestion = try #require(CommutativityTemplate.suggest(for: summary, vocabulary: vocabulary))
        // Score should be 30 + 40 - 30 = 40 → Possible.
        #expect(suggestion.score.total == 40)
        let counterLine = suggestion.explainability.whySuggested.first { line in
            line.contains("anti-commutativity")
        }
        #expect(counterLine == "Curated anti-commutativity verb match: 'subtract' (-30)")
    }

    // MARK: - Project vocabulary (commutativity verbs)

    @Test("Project-vocabulary verb on (T, T) -> T scores 70 (Likely)")
    func projectVocabularyVerb() {
        let summary = makeCommutativitySummary(
            name: "unionGraphs",
            returnType: "Graph",
            paramTypes: ("Graph", "Graph")
        )
        let vocabulary = Vocabulary(commutativityVerbs: ["unionGraphs"])
        let suggestion = CommutativityTemplate.suggest(for: summary, vocabulary: vocabulary)
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
    }

    @Test("Curated verb wins over project-vocabulary when both list the same name")
    func curatedTakesPrecedenceOverProjectVocabulary() throws {
        let summary = makeCommutativitySummary(
            name: "merge",
            returnType: "Set",
            paramTypes: ("Set", "Set")
        )
        let vocabulary = Vocabulary(commutativityVerbs: ["merge"])
        let suggestion = try #require(CommutativityTemplate.suggest(for: summary, vocabulary: vocabulary))
        #expect(suggestion.score.total == 70)
        let nameLine = suggestion.explainability.whySuggested.first { line in
            line.contains("verb match")
        }
        #expect(nameLine == "Curated commutativity verb match: 'merge' (+40)")
    }

    @Test("Empty vocabulary leaves curated behaviour unchanged")
    func emptyVocabularyLeavesCuratedAlone() {
        let summary = makeCommutativitySummary(
            name: "merge",
            returnType: "Set",
            paramTypes: ("Set", "Set")
        )
        let suggestion = CommutativityTemplate.suggest(for: summary, vocabulary: .empty)
        #expect(suggestion?.score.total == 70)
    }

    // MARK: - Vetoes

    @Test("Non-deterministic body veto suppresses regardless of name signal")
    func nonDeterministicVetoSuppresses() {
        let summary = makeCommutativitySummary(
            name: "merge",
            returnType: "Set",
            paramTypes: ("Set", "Set"),
            bodySignals: BodySignals(
                hasNonDeterministicCall: true,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: ["Date"]
            )
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }
}
