import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("RoundTripTemplate — project vocabulary (PRD §4.5)")
struct RoundTripTemplateVocabularyTests {

    @Test("Project-vocabulary pair scores 70 (Likely)")
    func projectVocabularyPair() {
        let pair = makeRoundTripPair(
            forwardName: "enqueue",
            reverseName: "dequeue",
            forwardParam: "Job",
            forwardReturn: "Job?"
        )
        let vocabulary = Vocabulary(
            inversePairs: [InversePair(forward: "enqueue", reverse: "dequeue")]
        )
        let suggestion = RoundTripTemplate.suggest(for: pair, vocabulary: vocabulary)
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
    }

    @Test("Project-vocabulary pair matches in either orientation")
    func projectVocabularyOrientationInsensitive() {
        let direct = makeRoundTripPair(
            forwardName: "enqueue",
            reverseName: "dequeue",
            forwardParam: "Job",
            forwardReturn: "Job?"
        )
        let swapped = makeRoundTripPair(
            forwardName: "dequeue",
            reverseName: "enqueue",
            forwardParam: "Job?",
            forwardReturn: "Job"
        )
        let vocabulary = Vocabulary(
            inversePairs: [InversePair(forward: "enqueue", reverse: "dequeue")]
        )
        #expect(RoundTripTemplate.suggest(for: direct, vocabulary: vocabulary)?.score.total == 70)
        #expect(RoundTripTemplate.suggest(for: swapped, vocabulary: vocabulary)?.score.total == 70)
    }

    @Test("Project-vocabulary signal renders with the project-vocab detail line")
    func projectVocabularyDetailLine() throws {
        let pair = makeRoundTripPair(
            forwardName: "enqueue",
            reverseName: "dequeue",
            forwardParam: "Job",
            forwardReturn: "Job?"
        )
        let vocabulary = Vocabulary(
            inversePairs: [InversePair(forward: "enqueue", reverse: "dequeue")]
        )
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair, vocabulary: vocabulary))
        let nameLine = suggestion.explainability.whySuggested.first { line in
            line.contains("inverse name pair")
        }
        #expect(nameLine == "Project-vocabulary inverse name pair: enqueue/dequeue (+40)")
    }

    @Test("Curated pair wins over a project-vocabulary list that repeats the same names")
    func curatedTakesPrecedenceOverProjectVocabulary() throws {
        let pair = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let vocabulary = Vocabulary(
            inversePairs: [InversePair(forward: "encode", reverse: "decode")]
        )
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair, vocabulary: vocabulary))
        #expect(suggestion.score.total == 70)
        let nameLine = suggestion.explainability.whySuggested.first { line in
            line.contains("inverse name pair")
        }
        #expect(nameLine == "Curated inverse name pair: encode/decode (+40)")
    }

    @Test("Empty vocabulary leaves curated behaviour unchanged")
    func emptyVocabularyLeavesCuratedAlone() {
        let pair = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair, vocabulary: .empty)
        #expect(suggestion?.score.total == 70)
    }

    @Test("Pair matching neither curated nor project-vocab still scores 30 baseline")
    func unmatchedPairScoresBaseline() {
        let pair = makeRoundTripPair(
            forwardName: "transform",
            reverseName: "untransform",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let vocabulary = Vocabulary(
            inversePairs: [InversePair(forward: "enqueue", reverse: "dequeue")]
        )
        let suggestion = RoundTripTemplate.suggest(for: pair, vocabulary: vocabulary)
        #expect(suggestion?.score.total == 30)
    }
}
