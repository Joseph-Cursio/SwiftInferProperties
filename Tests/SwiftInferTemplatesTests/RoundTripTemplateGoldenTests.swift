import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("RoundTripTemplate — @Discoverable +35 signal (M5.1)")
struct RoundTripTemplateDiscoverableTests {

    @Test("@Discoverable(group:) on both halves contributes +35 to a curated round-trip pair")
    func discoverableSignalLiftsCuratedPairScore() throws {
        let pair = makeRoundTripPair(
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
        let pair = makeRoundTripPair(
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
        let pair = makeRoundTripPair(
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
        let pair = makeRoundTripPair(
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
}

@Suite("RoundTripTemplate — golden renders")
struct RoundTripTemplateGoldenTests {

    @Test("Project-vocabulary Likely suggestion renders byte-for-byte")
    func projectVocabularyGoldenRender() throws {
        let pair = FunctionPair(
            forward: makeRoundTripCodecHalf(name: "enqueue", paramType: "Job", returnType: "Job?", line: 3),
            reverse: makeRoundTripCodecHalf(name: "dequeue", paramType: "Job?", returnType: "Job", line: 6)
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
            forward: makeRoundTripCodecHalf(name: "encode", paramType: "MyType", returnType: "Data", line: 3),
            reverse: makeRoundTripCodecHalf(name: "decode", paramType: "Data", returnType: "MyType", line: 6)
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
}
