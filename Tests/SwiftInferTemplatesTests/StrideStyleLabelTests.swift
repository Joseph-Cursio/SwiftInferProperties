import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// V1.22.D — stride-style label extension. Closes the cycle-14-demoted
/// Algo `endOfChunk(startingAt:) × startOfChunk(endingAt:)` triple
/// (round-trip + inverse-pair; idempotence out-of-scope per v1.22 plan
/// §"Workstream D" open decision #4).
@Suite("RoundTripTemplate + InversePairTemplate — V1.22.D stride-style label both-sides veto")
struct StrideStyleLabelTests {

    private func stridePair(
        forward: String = "endOfChunk",
        forwardLabel: String?,
        reverse: String = "startOfChunk",
        reverseLabel: String?
    ) -> FunctionPair {
        let forwardSummary = FunctionSummary(
            name: forward,
            parameters: [Parameter(label: forwardLabel, internalName: "x", typeText: "Base.Index", isInout: false)],
            returnTypeText: "Base.Index",
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: "ChunkedSequence",
            bodySignals: .empty
        )
        let reverseSummary = FunctionSummary(
            name: reverse,
            parameters: [Parameter(label: reverseLabel, internalName: "x", typeText: "Base.Index", isInout: false)],
            returnTypeText: "Base.Index",
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 5, column: 1),
            containingTypeName: "ChunkedSequence",
            bodySignals: .empty
        )
        return FunctionPair(forward: forwardSummary, reverse: reverseSummary)
    }

    // MARK: - Curated set membership

    @Test("StrideStyleLabels.curated contains the cycle-14 target labels (startingAt, endingAt)")
    func curatedContainsTargets() {
        for label in ["startingAt", "endingAt", "fromIndex", "toIndex", "from", "to", "startingFrom"] {
            #expect(StrideStyleLabels.curated.contains(label), "\(label) should be in curated set")
        }
    }

    @Test("StrideStyleLabels.curated does NOT overlap with DirectionLabels.curated")
    func noDirectionLabelsOverlap() {
        let overlap = StrideStyleLabels.curated.intersection(DirectionLabels.curated)
        #expect(overlap.isEmpty, "StrideStyle overlaps with Direction: \(overlap)")
    }

    // MARK: - RoundTripTemplate stride-style veto

    @Test("RoundTrip 'endOfChunk(startingAt:) × startOfChunk(endingAt:)' fires -25 (cycle-14 case)")
    func roundTripCycle14CaseFires() throws {
        let signal = RoundTripTemplate.strideStyleLabelCounterSignal(
            for: stridePair(forwardLabel: "startingAt", reverseLabel: "endingAt")
        )
        let veto = try #require(signal)
        #expect(veto.weight == -25)
        #expect(veto.detail.contains("Both pair sides stride-style-labeled"))
        #expect(veto.detail.contains("startingAt"))
        #expect(veto.detail.contains("endingAt"))
    }

    @Test("RoundTrip from/to labels both-sides fires -25")
    func roundTripFromToFires() {
        let signal = RoundTripTemplate.strideStyleLabelCounterSignal(
            for: stridePair(forwardLabel: "from", reverseLabel: "to")
        )
        #expect(signal?.weight == -25)
    }

    @Test("RoundTrip single-side stride-style does NOT fire (only both-sides)")
    func roundTripSingleSideDoesNotFire() {
        let signal = RoundTripTemplate.strideStyleLabelCounterSignal(
            for: stridePair(forwardLabel: "startingAt", reverseLabel: "after")
        )
        #expect(signal == nil, "Single-side stride-style is out of V1.22.D scope")
    }

    @Test("RoundTrip neither-side stride-style returns nil")
    func roundTripNeitherSideReturnsNil() {
        let signal = RoundTripTemplate.strideStyleLabelCounterSignal(
            for: stridePair(forwardLabel: "encode", reverseLabel: "decode")
        )
        #expect(signal == nil)
    }

    @Test("RoundTrip nil-labeled both sides returns nil")
    func roundTripNilLabelsReturnsNil() {
        let signal = RoundTripTemplate.strideStyleLabelCounterSignal(
            for: stridePair(forwardLabel: nil, reverseLabel: nil)
        )
        #expect(signal == nil)
    }

    // MARK: - InversePairTemplate stride-style veto

    @Test("InversePair 'endOfChunk(startingAt:) × startOfChunk(endingAt:)' fires -25")
    func inversePairCycle14CaseFires() throws {
        let signal = InversePairTemplate.strideStyleLabelCounterSignal(
            for: stridePair(forwardLabel: "startingAt", reverseLabel: "endingAt")
        )
        let veto = try #require(signal)
        #expect(veto.weight == -25)
        #expect(veto.detail.contains("Both pair sides stride-style-labeled"))
    }

    @Test("InversePair single-side stride-style does NOT fire")
    func inversePairSingleSideDoesNotFire() {
        let signal = InversePairTemplate.strideStyleLabelCounterSignal(
            for: stridePair(forwardLabel: "fromIndex", reverseLabel: "after")
        )
        #expect(signal == nil)
    }

    // MARK: - End-to-end RoundTripTemplate.suggest()

    @Test("End-to-end: stride-style round-trip suggestion is suppressed at v1.22.D")
    func endToEndRoundTripSuppressed() {
        let suggestion = RoundTripTemplate.suggest(
            for: stridePair(forwardLabel: "startingAt", reverseLabel: "endingAt")
        )
        // 30 typeSymmetry - 25 V1.22.D = +5 → Suppressed.
        #expect(suggestion == nil, "V1.22.D should suppress the cycle-14 demoted pair")
    }

    @Test("End-to-end: non-stride round-trip ('encode' × 'decode') still surfaces")
    func endToEndNonStridePreserves() {
        let suggestion = RoundTripTemplate.suggest(
            for: stridePair(
                forward: "encode",
                forwardLabel: nil,
                reverse: "decode",
                reverseLabel: nil
            )
        )
        // 30 typeSymmetry + ... = above Possible threshold.
        #expect(suggestion != nil)
    }
}
