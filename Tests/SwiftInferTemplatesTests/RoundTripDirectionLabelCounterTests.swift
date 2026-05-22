import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// V1.12.1 — direction-label counter-signal on RoundTripTemplate.
// Closes cycle-9 priority #1 from
// docs/calibration-cycle-8-findings.md (round-trip template direction-
// label counter — third consumer of Signal.Kind.directionLabel +
// the curated direction set).
//
// Mirrors v1.10's IdempotenceDirectionLabelCounterTests and v1.11's
// InversePairDirectionLabelCounterTests shape.
//
// V1.13.1 — direction-label set hoisted from
// IdempotenceTemplate.directionLabels to
// SwiftInferCore.DirectionLabels.curated; round-trip's landing as the
// third consumer in cycle 9 was the trigger for the hoist. The set
// now lives alongside Signal.Kind.directionLabel in core, factored as
// a shared three-template utility.
//
// Score arithmetic (round-trip baseline +30 typeSymmetry, matching
// idempotence's +30 — not inverse-pair's +25 which justified v1.11's
// -10 weight):
//   bare typeSymmetry           : +30        → Possible
//   bare + direction counter    : +30 - 15 = +15  → Suppressed
//   curated name (+40)          : +30 + 40 = +70  → Likely
//   curated name + direction    : +30 + 40 - 15 = +55  → Likely (preserved)
//   discoverable (+35)          : +30 + 35 = +65  → Likely
//   discoverable + direction    : +30 + 35 - 15 = +50  → Likely (preserved)
//   cross-type (-25)            : +30 - 25 = +5   → Suppressed
//   cross-type + direction      : +30 - 25 - 15 = -10  → Suppressed (deeper)

@Suite("RoundTripTemplate — V1.12.1 direction-label counter-signal")
struct RoundTripDirectionLabelCounterTests {

    // MARK: - Suppression cases (the dominant Algo round-trip pattern)

    @Test("V1.12.1 — `index(after:) ↔ index(before:)` is suppressed (+30 - 15 = +15)")
    func indexAfterIndexBeforeSuppressed() {
        // The textbook cycle-9 case: 18 of 20 Algo round-trip Possible-
        // tier suggestions are this exact shape across distinct source
        // files. Score arithmetic: typeSymmetry +30, direction counter
        // -15 = +15 → Suppressed tier (< 20).
        let pair = makePair(
            forwardName: "index",
            forwardLabel: "after",
            reverseName: "index",
            reverseLabel: "before",
            forwardParam: "Index",
            forwardReturn: "Index"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion == nil, "Direction-labeled round-trip pair should be suppressed")
    }

    @Test("V1.12.1 — `index(after:) ↔ index(after:)` cross-file self-pair is suppressed")
    func indexAfterCrossFileSelfPairSuppressed() {
        // Cross-file self-pair shape: same `index(after:)` declared on
        // two distinct conforming types. Either-side detection fires
        // because both labels are in the curated set.
        let forward = makeSummary(
            name: "index",
            label: "after",
            paramType: "Index",
            returnType: "Index",
            line: 100,
            file: "FileA.swift"
        )
        let reverse = makeSummary(
            name: "index",
            label: "after",
            paramType: "Index",
            returnType: "Index",
            line: 200,
            file: "FileB.swift"
        )
        let suggestion = RoundTripTemplate.suggest(for: FunctionPair(forward: forward, reverse: reverse))
        #expect(suggestion == nil)
    }

    @Test(
        "V1.12.1 — all curated direction labels suppress (forward-side)",
        arguments: ["after", "before", "next", "prev", "previous",
                    "advance", "succ", "pred", "successor", "predecessor"]
    )
    func allCuratedDirectionLabelsSuppressForwardSide(label: String) {
        let pair = makePair(
            forwardName: "step",
            forwardLabel: label,
            reverseName: "unstep",
            reverseLabel: nil,
            forwardParam: "Token",
            forwardReturn: "Token"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion == nil, "Forward direction label '\(label)' should suppress")
    }

    @Test(
        "V1.12.1 — direction label on reverse side alone also suppresses",
        arguments: ["after", "before", "next", "prev", "previous",
                    "advance", "succ", "pred", "successor", "predecessor"]
    )
    func directionLabelOnReverseSuppresses(label: String) {
        // Either-side detection (open decision #3): asymmetric labeling
        // should still suppress. Non-curated names so the baseline is
        // bare typeSymmetry +30; reverse-side direction label -15 = +15
        // → Suppressed.
        let pair = makePair(
            forwardName: "transform",
            forwardLabel: nil,
            reverseName: "untransform",
            reverseLabel: label,
            forwardParam: "Token",
            forwardReturn: "Token"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion == nil, "Reverse direction label '\(label)' should suppress")
    }

    // MARK: - Non-suppression cases (preserve well-named round-trip pairs)

    // V1.12.1 — `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` (stride labels)
    // — direction-counter does NOT fire (stride labels aren't in DirectionLabels.curated)
    @Test("V1.12.1 — stride-style labels do NOT fire the direction-counter")
    func strideStyleLabelsDoNotFireDirectionCounter() {
        // V1.12.1's direction-counter does NOT fire on stride-style
        // labels (which are in StrideStyleLabels.curated, NOT
        // DirectionLabels.curated). The pair was previously surfaced
        // at score 30 → Possible — but V1.22.D's stride-style both-sides
        // veto now fires at -25, suppressing the suggestion entirely.
        // This test verifies V1.12.1's directionLabelCounterSignal
        // does NOT fire on stride labels (the V1.22.D veto fires
        // separately and is tested in StrideStyleLabelTests).
        let pair = makePair(
            forwardName: "endOfChunk",
            forwardLabel: "startingAt",
            reverseName: "startOfChunk",
            reverseLabel: "endingAt",
            forwardParam: "Index",
            forwardReturn: "Index"
        )
        // V1.12.1 directionLabelCounterSignal returns nil — stride
        // labels aren't in DirectionLabels.curated.
        #expect(RoundTripTemplate.directionLabelCounterSignal(for: pair) == nil)
        // V1.22.D strideStyleLabelCounterSignal fires at -25 — both
        // labels are in StrideStyleLabels.curated.
        #expect(RoundTripTemplate.strideStyleLabelCounterSignal(for: pair)?.weight == -25)
        // End-to-end suggest is now Suppressed (not Possible like pre-V1.22.D).
        #expect(RoundTripTemplate.suggest(for: pair) == nil)
    }

    @Test("V1.12.1 — curated `encode/decode` pair (no direction labels) still surfaces Likely")
    func curatedEncodeDecodeStillSurfacesLikely() {
        // Curated-name match +40, typeSymmetry +30 → +70 Likely. No
        // direction counter fires. This is the bread-and-butter round-
        // trip case the user explicitly cares about; v1.12 must not
        // touch it.
        let pair = makePair(
            forwardName: "encode",
            forwardLabel: nil,
            reverseName: "decode",
            reverseLabel: nil,
            forwardParam: "Document",
            forwardReturn: "Data"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
    }

    @Test("V1.12.1 — curated `encode/decode` with direction label on one side stays Likely (+30 + 40 - 15 = +55)")
    func curatedNameWithDirectionLabelStaysLikely() {
        // Hypothetical asymmetric: `encode(_:) × decode(after:)`. Curated
        // name match +40 dominates, direction counter -15 nicks 15 off,
        // net +55 → Likely (clean preservation, well above the +40
        // boundary). Mirrors v1.11's "curated-name preserves above the
        // boundary" design intent at the round-trip baseline.
        let pair = makePair(
            forwardName: "encode",
            forwardLabel: nil,
            reverseName: "decode",
            reverseLabel: "after",
            forwardParam: "Document",
            forwardReturn: "Data"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion?.score.total == 55)
        #expect(suggestion?.score.tier == .likely)
        #expect(suggestion?.score.signals.contains { $0.kind == .directionLabel } ?? false)
        #expect(suggestion?.score.signals.contains { $0.kind == .exactNameMatch } ?? false)
    }

    @Test("V1.12.1 — `forScale ↔ forCapacity` not in V1.13.1 direction-label set (counter does not fire)")
    func directionCounterDoesNotFireOnDomainMarkers() {
        // OC HashTable Constants survivors shape: `minimumCapacity(forScale:)
        // ↔ scale(forCapacity:)`. The V1.13.1 direction-label set
        // (`{after, before, next, prev, ...}`) is disjoint from the
        // V1.15.1 domain-marker set; the V1.12.1 direction-label counter
        // does not fire on these labels.
        //
        // **V1.15.1 update**: this case is now suppressed by the V1.15.1
        // domain-marker counter (separate mechanism on the same Signal.Kind
        // case). The test verifies the V1.12.1 contract — direction counter
        // doesn't fire — while the V1.15.1 RoundTripDomainMarkerCounterTests
        // suite verifies the v1.15 suppression separately.
        let pair = makePair(
            forwardName: "minimumCapacity",
            forwardLabel: "forScale",
            reverseName: "scale",
            reverseLabel: "forCapacity",
            forwardParam: "Int",
            forwardReturn: "Int"
        )
        // V1.15.1: pair is now Suppressed via the domain-marker counter.
        // Verify the V1.12.1 direction counter specifically didn't fire by
        // asking it directly — the round-level suggest() returns nil because
        // the domain-marker counter suppresses, but the direction-counter
        // helper itself returns nil for these labels.
        let directionSignal = RoundTripTemplate.directionLabelCounterSignal(for: pair)
        #expect(directionSignal == nil, "V1.13.1 direction-label set must not contain forScale/forCapacity")
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion == nil, "V1.15.1 domain-marker counter suppresses this case")
    }

    @Test("V1.12.1 — both nil labels → no direction counter (+30 Possible)")
    func nilLabelsDoNotSuppress() {
        let pair = makePair(
            forwardName: "transform",
            forwardLabel: nil,
            reverseName: "untransform",
            reverseLabel: nil,
            forwardParam: "Token",
            forwardReturn: "Bytes"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion?.score.total == 30)
        #expect(!(suggestion?.score.signals.contains { $0.kind == .directionLabel } ?? false))
    }

    // MARK: - Boundary + design cases

    @Test("V1.12.1 — direction label is case-sensitive (`After` does not suppress)")
    func caseSensitive() {
        let pair = makePair(
            forwardName: "step",
            forwardLabel: "After",
            reverseName: "unstep",
            reverseLabel: "Before",
            forwardParam: "Token",
            forwardReturn: "Token"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion?.score.total == 30, "Mismatched case shouldn't trigger the counter")
    }

    @Test("V1.12.1 — counter weight is exactly -15 (mirrors v1.10 idempotence)")
    func counterWeightIsMinusFifteen() {
        // The weight is the load-bearing calibration choice. Round-trip's
        // +30 baseline matches idempotence's, so -15 ports verbatim. A
        // regression to -10 would land bare-shape pairs at +20 — exactly
        // on the Possible/Suppressed boundary, the noisy zone v1.10/v1.11
        // open-decision-#1 explicitly avoided.
        let curated = makePair(
            forwardName: "encode",
            forwardLabel: "after",
            reverseName: "decode",
            reverseLabel: nil,
            forwardParam: "Document",
            forwardReturn: "Data"
        )
        let suggestion = RoundTripTemplate.suggest(for: curated)
        let directionSignal = suggestion?.score.signals.first { $0.kind == .directionLabel }
        #expect(directionSignal?.weight == -15)
        // Sanity check: bare-shape with direction label suppresses.
        let bare = makePair(
            forwardName: "step",
            forwardLabel: "after",
            reverseName: "unstep",
            reverseLabel: nil,
            forwardParam: "Token",
            forwardReturn: "Token"
        )
        #expect(RoundTripTemplate.suggest(for: bare) == nil)
    }

    @Test("V1.13.1 — directionLabels live at SwiftInferCore.DirectionLabels.curated (post-hoist)")
    func reusesSharedDirectionLabels() {
        // v1.12 originally consumed IdempotenceTemplate.directionLabels
        // via cross-template static access. V1.13.1 hoisted the set to
        // SwiftInferCore.DirectionLabels.curated once round-trip made
        // it a three-consumer utility — the hoist is zero-behavior-change
        // (set elements identical), pure site-of-truth cleanup.
        #expect(DirectionLabels.curated.count == 10)
        let expected: Set<String> = [
            "after", "before",
            "next", "prev", "previous",
            "advance", "succ", "pred", "successor", "predecessor"
        ]
        #expect(DirectionLabels.curated == expected)
    }

    // MARK: - Fixtures

    private func makePair(
        forwardName: String,
        forwardLabel: String? = nil,
        reverseName: String,
        reverseLabel: String? = nil,
        forwardParam: String,
        forwardReturn: String
    ) -> FunctionPair {
        let forward = makeSummary(
            name: forwardName,
            label: forwardLabel,
            paramType: forwardParam,
            returnType: forwardReturn,
            line: 10
        )
        let reverse = makeSummary(
            name: reverseName,
            label: reverseLabel,
            paramType: forwardReturn,
            returnType: forwardParam,
            line: 20
        )
        return FunctionPair(forward: forward, reverse: reverse)
    }

    private func makeSummary(
        name: String,
        label: String?,
        paramType: String,
        returnType: String,
        line: Int,
        file: String = "Test.swift"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: label, internalName: "x", typeText: paramType, isInout: false)],
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: file, line: line, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }
}
