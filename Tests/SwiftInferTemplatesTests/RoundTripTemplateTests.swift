import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

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

    @Test("Likely suggestion renders byte-for-byte against the M1 acceptance-bar golden")
    func likelyRoundTripGoldenRender() throws {
        let forward = FunctionSummary(
            name: "encode",
            parameters: [Parameter(label: nil, internalName: "value", typeText: "MyType", isInout: false)],
            returnTypeText: "Data",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Sources/Demo/Codec.swift", line: 3, column: 5),
            containingTypeName: "Codec",
            bodySignals: .empty
        )
        let reverse = FunctionSummary(
            name: "decode",
            parameters: [Parameter(label: nil, internalName: "data", typeText: "Data", isInout: false)],
            returnTypeText: "MyType",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Sources/Demo/Codec.swift", line: 6, column: 5),
            containingTypeName: "Codec",
            bodySignals: .empty
        )
        let pair = FunctionPair(forward: forward, reverse: reverse)
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair))
        let rendered = SuggestionRenderer.render(suggestion)
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
Sampling:  not run (M4 deferred)
"""
        #expect(rendered == expected)
    }

    // MARK: - Helpers

    private func makePair(
        forwardName: String,
        reverseName: String,
        forwardParam: String,
        forwardReturn: String,
        forwardBodySignals: BodySignals = .empty,
        reverseBodySignals: BodySignals = .empty
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
            bodySignals: forwardBodySignals
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
            bodySignals: reverseBodySignals
        )
        return FunctionPair(forward: forward, reverse: reverse)
    }
}
