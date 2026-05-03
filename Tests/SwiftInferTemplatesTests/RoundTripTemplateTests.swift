import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("RoundTripTemplate — pair shape + curated naming + vetoes")
struct RoundTripTemplateBasicsTests {

    @Test("Pair without curated name match scores 30 (Possible)")
    func typeShapeAlone() {
        let pair = makeRoundTripPair(
            forwardName: "transform",
            reverseName: "untransform",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion?.score.total == 30)
        #expect(suggestion?.score.tier == .possible)
    }

    @Test("Curated inverse name pair scores 70 (Likely)")
    func curatedInverseNamePair() {
        let pair = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
    }

    @Test("Curated match works regardless of pair orientation")
    func curatedMatchOrientationInsensitive() {
        let direct = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let swapped = makeRoundTripPair(
            forwardName: "decode",
            reverseName: "encode",
            forwardParam: "Data",
            forwardReturn: "MyType"
        )
        #expect(RoundTripTemplate.suggest(for: direct)?.score.total == 70)
        #expect(RoundTripTemplate.suggest(for: swapped)?.score.total == 70)
    }

    @Test("Non-deterministic API in either body suppresses the suggestion")
    func nonDeterministicVeto() {
        let pair = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data",
            forwardBodySignals: BodySignals(
                hasNonDeterministicCall: true,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: ["Date"]
            )
        )
        #expect(RoundTripTemplate.suggest(for: pair) == nil)
    }

    @Test("Non-deterministic API in the reverse body also vetoes")
    func reverseBodyVeto() {
        let pair = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data",
            reverseBodySignals: BodySignals(
                hasNonDeterministicCall: true,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: ["UUID"]
            )
        )
        #expect(RoundTripTemplate.suggest(for: pair) == nil)
    }

    @Test("Suggestion carries both halves as Evidence")
    func bothHalvesInEvidence() throws {
        let pair = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair))
        #expect(suggestion.evidence.count == 2)
        #expect(suggestion.evidence[0].displayName == "encode(_:)")
        #expect(suggestion.evidence[1].displayName == "decode(_:)")
    }

    @Test("Generator and sampling are M1 placeholders")
    func m1PlaceholderGenerator() throws {
        let pair = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair))
        #expect(suggestion.generator.source == .notYetComputed)
        #expect(suggestion.generator.sampling == .notRun)
    }

    @Test("Throws + Equatable caveats always populate the wrong-side block")
    func caveatsAlwaysPresent() throws {
        let pair = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair))
        #expect(suggestion.explainability.whyMightBeWrong.count == 2)
        #expect(suggestion.explainability.whyMightBeWrong[0].contains("Throws"))
        #expect(suggestion.explainability.whyMightBeWrong[1].contains("Equatable"))
    }
}

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

// MARK: - Shared helpers

func makeRoundTripCodecHalf(
    name: String,
    paramType: String,
    returnType: String,
    line: Int
) -> FunctionSummary {
    FunctionSummary(
        name: name,
        parameters: [Parameter(label: nil, internalName: "value", typeText: paramType, isInout: false)],
        returnTypeText: returnType,
        isThrows: false,
        isAsync: false,
        isMutating: false,
        isStatic: false,
        location: SourceLocation(file: "Sources/Demo/Codec.swift", line: line, column: 5),
        containingTypeName: "Codec",
        bodySignals: .empty
    )
}

func makeRoundTripPair(
    forwardName: String,
    reverseName: String,
    forwardParam: String,
    forwardReturn: String,
    forwardBodySignals: BodySignals = .empty,
    reverseBodySignals: BodySignals = .empty,
    forwardGroup: String? = nil,
    reverseGroup: String? = nil
) -> FunctionPair {
    let forward = FunctionSummary(
        name: forwardName,
        parameters: [Parameter(label: nil, internalName: "x", typeText: forwardParam, isInout: false)],
        returnTypeText: forwardReturn,
        isThrows: false,
        isAsync: false,
        isMutating: false,
        isStatic: false,
        location: SourceLocation(file: "Test.swift", line: 1, column: 1),
        containingTypeName: nil,
        bodySignals: forwardBodySignals,
        discoverableGroup: forwardGroup
    )
    let reverse = FunctionSummary(
        name: reverseName,
        parameters: [Parameter(label: nil, internalName: "x", typeText: forwardReturn, isInout: false)],
        returnTypeText: forwardParam,
        isThrows: false,
        isAsync: false,
        isMutating: false,
        isStatic: false,
        location: SourceLocation(file: "Test.swift", line: 5, column: 1),
        containingTypeName: nil,
        bodySignals: reverseBodySignals,
        discoverableGroup: reverseGroup
    )
    return FunctionPair(forward: forward, reverse: reverse)
}
