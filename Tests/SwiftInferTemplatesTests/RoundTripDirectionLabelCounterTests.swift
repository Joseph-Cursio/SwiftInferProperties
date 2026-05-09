import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

// V1.12.1 — direction-label counter-signal on RoundTripTemplate.
// Closes cycle-9 priority #1 from
// docs/calibration-cycle-8-findings.md (round-trip template direction-
// label counter — third consumer of Signal.Kind.directionLabel +
// IdempotenceTemplate.directionLabels).
//
// Mirrors v1.10's IdempotenceDirectionLabelCounterTests and v1.11's
// InversePairDirectionLabelCounterTests shape; reuses
// IdempotenceTemplate.directionLabels via cross-template static access
// (open decision #2 in v1.12 plan; v1.13 hoists to a shared namespace).
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

    @Test("V1.12.1 — `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` (stride labels) still emits Possible")
    func strideStyleLabelsDoNotSuppress() {
        // Stride-style labels (`startingAt`, `endingAt`) are NOT in the
        // curated direction set per v1.11 open decision #4 carried
        // forward into v1.12. Counter does not fire; baseline typeSymmetry
        // +30 → Possible. Cycle-10 candidate to extend the curated set.
        let pair = makePair(
            forwardName: "endOfChunk",
            forwardLabel: "startingAt",
            reverseName: "startOfChunk",
            reverseLabel: "endingAt",
            forwardParam: "Index",
            forwardReturn: "Index"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion?.score.tier == .possible)
        #expect(!(suggestion?.score.signals.contains { $0.kind == .directionLabel } ?? false))
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

    @Test("V1.12.1 — non-direction-labeled pair (`forScale`) does not fire counter")
    func nonDirectionLabelDoesNotSuppress() {
        // OC HashTable Constants survivors shape: `minimumCapacity(forScale:)`
        // — `forScale` not in curated set. Counter does not fire.
        // Baseline typeSymmetry +30 → Possible. Cycle-10 domain-mismatch
        // mechanism is the eventual fix here.
        let pair = makePair(
            forwardName: "minimumCapacity",
            forwardLabel: "forScale",
            reverseName: "scale",
            reverseLabel: "forCapacity",
            forwardParam: "Int",
            forwardReturn: "Int"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion?.score.total == 30)
        #expect(suggestion?.score.tier == .possible)
        #expect(!(suggestion?.score.signals.contains { $0.kind == .directionLabel } ?? false))
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
        let directionSignal = suggestion?.score.signals.first(where: { $0.kind == .directionLabel })
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

    @Test("V1.12.1 — directionLabels reused from IdempotenceTemplate (third consumer)")
    func reusesIdempotenceCuratedSet() {
        // v1.12 reuses the v1.10 curated set as-is rather than
        // duplicating. With round-trip making the third consumer,
        // hoisting to a shared `SwiftInferCore.DirectionLabels` namespace
        // becomes the natural v1.13 atomic refactor (zero behavior change).
        #expect(IdempotenceTemplate.directionLabels.count == 10)
        let expected: Set<String> = [
            "after", "before",
            "next", "prev", "previous",
            "advance", "succ", "pred", "successor", "predecessor"
        ]
        #expect(IdempotenceTemplate.directionLabels == expected)
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
