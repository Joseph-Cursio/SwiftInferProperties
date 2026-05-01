import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

// swiftlint:disable type_body_length file_length
// Test suites cohere around their subject — splitting along the 250-line
// body limit would scatter the round-trip-template assertions across
// multiple files for no reader benefit.
@Suite("RoundTripTemplate — pair shape, name match, vetoes, caveats")
struct RoundTripTemplateTests {

    @Test("Pair without curated name match scores 30 (Possible)")
    func typeShapeAlone() {
        let pair = makePair(
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
        let pair = makePair(
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
        let direct = makePair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let swapped = makePair(
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
        let pair = makePair(
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
        let pair = makePair(
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
        let pair = makePair(
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
        let pair = makePair(
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
        let pair = makePair(
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

    // MARK: - Project vocabulary (PRD §4.5)

    @Test("Project-vocabulary pair scores 70 (Likely)")
    func projectVocabularyPair() {
        let pair = makePair(
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
        let direct = makePair(
            forwardName: "enqueue",
            reverseName: "dequeue",
            forwardParam: "Job",
            forwardReturn: "Job?"
        )
        let swapped = makePair(
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
        let pair = makePair(
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
        let pair = makePair(
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
        let pair = makePair(
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
        let pair = makePair(
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

    @Test("Project-vocabulary Likely suggestion renders byte-for-byte")
    func projectVocabularyGoldenRender() throws {
        let pair = FunctionPair(
            forward: makeCodecHalf(name: "enqueue", paramType: "Job", returnType: "Job?", line: 3),
            reverse: makeCodecHalf(name: "dequeue", paramType: "Job?", returnType: "Job", line: 6)
        )
        let vocabulary = Vocabulary(
            inversePairs: [InversePair(forward: "enqueue", reverse: "dequeue")]
        )
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair, vocabulary: vocabulary))
        let rendered = SuggestionRenderer.render(suggestion)
        let seedHex = SamplingSeed.renderHex(SamplingSeed.derive(from: suggestion.identity))
        let expected = """
[Suggestion]
Template: round-trip
Score:    70 (Likely)

Why suggested:
  ✓ enqueue(_:) (Job) -> Job? — Sources/Demo/Codec.swift:3
  ✓ dequeue(_:) (Job?) -> Job — Sources/Demo/Codec.swift:6
  ✓ Type-symmetry signature: Job -> Job? ↔ Job? -> Job (+30)
  ✓ Project-vocabulary inverse name pair: enqueue/dequeue (+40)

Why this might be wrong:
  ⚠ Throws on either side narrows the property's domain to the success set \
of the inner function; a generator that produces values outside that set \
will surface false-positive failures (Appendix B.4).
  ⚠ T must conform to Equatable for the emitted property to compile. \
SwiftInfer M1 does not verify protocol conformance — confirm before applying.

Generator: not yet computed (M3 prerequisite)
Sampling:  not run; lifted test seed: \(seedHex)
Identity:  \(suggestion.identity.display)
Suppress:  // swiftinfer: skip \(suggestion.identity.display)
"""
        #expect(rendered == expected)
    }

    @Test("Likely suggestion renders byte-for-byte against the M1 acceptance-bar golden")
    func likelyRoundTripGoldenRender() throws {
        let pair = FunctionPair(
            forward: makeCodecHalf(name: "encode", paramType: "MyType", returnType: "Data", line: 3),
            reverse: makeCodecHalf(name: "decode", paramType: "Data", returnType: "MyType", line: 6)
        )
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair))
        let rendered = SuggestionRenderer.render(suggestion)
        let seedHex = SamplingSeed.renderHex(SamplingSeed.derive(from: suggestion.identity))
        let expected = """
[Suggestion]
Template: round-trip
Score:    70 (Likely)

Why suggested:
  ✓ encode(_:) (MyType) -> Data — Sources/Demo/Codec.swift:3
  ✓ decode(_:) (Data) -> MyType — Sources/Demo/Codec.swift:6
  ✓ Type-symmetry signature: MyType -> Data ↔ Data -> MyType (+30)
  ✓ Curated inverse name pair: encode/decode (+40)

Why this might be wrong:
  ⚠ Throws on either side narrows the property's domain to the success set \
of the inner function; a generator that produces values outside that set \
will surface false-positive failures (Appendix B.4).
  ⚠ T must conform to Equatable for the emitted property to compile. \
SwiftInfer M1 does not verify protocol conformance — confirm before applying.

Generator: not yet computed (M3 prerequisite)
Sampling:  not run; lifted test seed: \(seedHex)
Identity:  0x4C3618BEBBE59391
Suppress:  // swiftinfer: skip 0x4C3618BEBBE59391
"""
        #expect(rendered == expected)
    }

    // MARK: - @Discoverable +35 signal (M5.1)

    @Test("@Discoverable(group:) on both halves contributes +35 to a curated round-trip pair")
    func discoverableSignalLiftsCuratedPairScore() throws {
        let pair = makePair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data",
            forwardGroup: "codec",
            reverseGroup: "codec"
        )
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair))
        // 30 type + 40 curated encode/decode + 35 discoverable = 105 → Strong.
        #expect(suggestion.score.total == 105)
        #expect(suggestion.score.tier == .strong)
        let discoverable = try #require(
            suggestion.score.signals.first { $0.kind == .discoverableAnnotation }
        )
        #expect(discoverable.weight == 35)
        #expect(discoverable.detail.contains("codec"))
    }

    @Test("@Discoverable(group:) lifts an otherwise-Possible non-curated pair into Likely")
    func discoverableSignalLiftsNonCuratedPair() throws {
        // No curated naming match — only the +30 type-symmetry signal
        // would normally land this at Possible (30 → Possible).
        // The +35 from a same-group @Discoverable lifts it to 65 → Likely.
        let pair = makePair(
            forwardName: "transform",
            reverseName: "untransform",
            forwardParam: "MyType",
            forwardReturn: "Data",
            forwardGroup: "codec",
            reverseGroup: "codec"
        )
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair))
        #expect(suggestion.score.total == 65)
        #expect(suggestion.score.tier == .likely)
    }

    @Test("Mismatched @Discoverable groups do NOT contribute the +35 signal")
    func discoverableSignalSkippedOnGroupMismatch() throws {
        let pair = makePair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data",
            forwardGroup: "codec",
            reverseGroup: "queue"
        )
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair))
        // 30 type + 40 curated = 70 (no +35) → Likely.
        #expect(suggestion.score.total == 70)
        #expect(!suggestion.score.signals.contains { $0.kind == .discoverableAnnotation })
    }

    @Test("One-sided @Discoverable does NOT contribute the +35 signal")
    func discoverableSignalSkippedOnOneSidedAnnotation() throws {
        let pair = makePair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data",
            forwardGroup: "codec",
            reverseGroup: nil
        )
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair))
        #expect(suggestion.score.total == 70)
        #expect(!suggestion.score.signals.contains { $0.kind == .discoverableAnnotation })
    }

    // MARK: - Helpers

    private func makeCodecHalf(
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

    private func makePair(
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
}
// swiftlint:enable type_body_length file_length
