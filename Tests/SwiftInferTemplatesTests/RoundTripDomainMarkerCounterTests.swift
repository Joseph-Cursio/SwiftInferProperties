import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// V1.15.1 — domain-marker counter-signal on RoundTripTemplate.
// Closes post-v1.14 priority #1: 9 OC HashTable round-trip Possible-
// tier survivors with both pair sides' first-parameter labels in
// DomainMarkerLabels.curated (forScale / forCapacity).
//
// Both-sides detection per V1.15.0 plan open decision #2: preserves
// the asymmetric `_value(forBucketContents:) ↔ _bucketContents(for:)`
// candidate which is likely a true-positive round-trip pair.
//
// Score arithmetic for round-trip (baseline +30 typeSymmetry):
//   bare typeSymmetry            : +30  → Possible
//   bare + domain-marker counter : +30 - 15 = +15 → Suppressed
//   curated encode/decode (+40)  : +40 + 30 = +70 → Likely
//   curated + counter            : +70 - 15 = +55 → Likely (preserved)
//   cross-type (-25) + counter   : +30 - 25 - 15 = -10 → Suppressed

@Suite("RoundTripTemplate — V1.15.1 domain-marker counter-signal")
struct RoundTripDomainMarkerCounterTests {

    // MARK: - Suppression cases (the cycle-11 OC HashTable survivor pattern)

    @Test("V1.15.1 — `min(forScale:) ↔ max(forScale:)` Int->Int pair is suppressed")
    func sameForScalePairSuppressed() {
        let pair = makePair(
            forwardName: "minimumCapacity", forwardLabel: "forScale",
            reverseName: "maximumCapacity", reverseLabel: "forScale",
            paramType: "Int", returnType: "Int"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion == nil, "Both-sides forScale pair should be suppressed")
    }

    @Test("V1.15.1 — `min(forScale:) ↔ scale(forCapacity:)` cross-domain pair is suppressed")
    func crossDomainForScaleForCapacityPairSuppressed() {
        let pair = makePair(
            forwardName: "minimumCapacity", forwardLabel: "forScale",
            reverseName: "scale", reverseLabel: "forCapacity",
            paramType: "Int", returnType: "Int"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion == nil, "Cross-domain forScale↔forCapacity pair should be suppressed")
    }

    @Test(
        "V1.15.1 — all 9 curated × curated combinations suppress",
        arguments: ["forScale", "forCapacity", "forBucketContents"],
                   ["forScale", "forCapacity", "forBucketContents"]
    )
    func allCuratedCombinationsSuppress(forward: String, reverse: String) {
        let pair = makePair(
            forwardName: "fwd", forwardLabel: forward,
            reverseName: "rev", reverseLabel: reverse,
            paramType: "Int", returnType: "Int"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion == nil, "\(forward) ↔ \(reverse) should suppress")
    }

    // MARK: - Non-suppression cases

    @Test("V1.15.1 — asymmetric `_value(forBucketContents:) ↔ _bucketContents(for:)` preserved")
    func asymmetricForLabelPairPreserved() {
        // Per V1.15.0 plan open decision #2: both-sides detection
        // preserves the cycle-11 OC asymmetric candidate which is
        // likely a true-positive round-trip pair (`for:` is the
        // unlabeled-domain "given X" carrier; only one side has the
        // explicit semantic-intent marker).
        let pair = makePair(
            forwardName: "_value", forwardLabel: "forBucketContents",
            reverseName: "_bucketContents", reverseLabel: "for",
            paramType: "UInt64", returnType: "Int"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        let hasDomainMarker = suggestion?.score.signals.contains { signal in
            signal.kind == .directionLabel && signal.weight == -15
                && signal.detail.contains("Domain-marker")
        } ?? false
        #expect(!hasDomainMarker, "One-side-labeled pair should not trigger domain-marker counter")
    }

    @Test("V1.15.1 — `encode(_:) ↔ decode(_:)` (curated names) stays Likely without domain markers")
    func curatedNamesNoLabelStillLikely() {
        let pair = makePair(
            forwardName: "encode", forwardLabel: nil,
            reverseName: "decode", reverseLabel: nil,
            paramType: "Data", returnType: "Token"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion?.score.tier == .likely)
        let hasDomainMarker = suggestion?.score.signals.contains { signal in
            signal.detail.contains("Domain-marker")
        } ?? false
        #expect(!hasDomainMarker)
    }

    @Test("V1.15.1 — non-domain `for` label (not in curated set) does NOT trigger counter")
    func nonCuratedForLabelDoesNotTrigger() {
        let pair = makePair(
            forwardName: "fwd", forwardLabel: "forSlot",
            reverseName: "rev", reverseLabel: "forIndex",
            paramType: "Int", returnType: "Int"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        let hasDomainMarker = suggestion?.score.signals.contains { signal in
            signal.detail.contains("Domain-marker")
        } ?? false
        #expect(!hasDomainMarker, "forSlot/forIndex are not in curated set")
    }

    // MARK: - Boundary + design + composition cases

    @Test("V1.15.1 — counter weight is exactly -15")
    func counterWeightIsMinusFifteen() {
        let pair = makePair(
            forwardName: "fwd", forwardLabel: "forScale",
            reverseName: "rev", reverseLabel: "forCapacity",
            paramType: "Int", returnType: "Int"
        )
        let signal = RoundTripTemplate.domainMarkerCounterSignal(for: pair)
        #expect(signal?.weight == -15)
        #expect(signal?.kind == .directionLabel)
    }

    @Test("V1.15.1 — case-sensitive (`ForScale` does not trigger)")
    func caseSensitive() {
        let pair = makePair(
            forwardName: "fwd", forwardLabel: "ForScale",
            reverseName: "rev", reverseLabel: "ForCapacity",
            paramType: "Int", returnType: "Int"
        )
        let signal = RoundTripTemplate.domainMarkerCounterSignal(for: pair)
        #expect(signal == nil, "Case-mismatched labels should not trigger counter")
    }

    @Test("V1.15.1 — domain-marker counter composes correctly with cross-type counter")
    func crossTypeAndDomainMarkerCompose() {
        // Hypothetical cross-type forScale pair: forward on TypeA,
        // reverse on TypeB. Cross-type -25 + domain marker -15 +
        // typeSymmetry +30 = -10 → Suppressed.
        let pair = makeCrossTypePair(
            forwardLabel: "forScale", reverseLabel: "forCapacity",
            paramType: "Int", returnType: "Int"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion == nil, "Cross-type + domain-marker should compose to Suppressed")
    }

    // MARK: - Fixtures

    private func makePair(
        forwardName: String,
        forwardLabel: String? = nil,
        reverseName: String,
        reverseLabel: String? = nil,
        paramType: String,
        returnType: String
    ) -> FunctionPair {
        let forward = FunctionSummary(
            name: forwardName,
            parameters: [Parameter(label: forwardLabel, internalName: "x", typeText: paramType, isInout: false)],
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let reverse = FunctionSummary(
            name: reverseName,
            parameters: [Parameter(label: reverseLabel, internalName: "x", typeText: returnType, isInout: false)],
            returnTypeText: paramType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 5, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        return FunctionPair(forward: forward, reverse: reverse)
    }

    private func makeCrossTypePair(
        forwardLabel: String?,
        reverseLabel: String?,
        paramType: String,
        returnType: String
    ) -> FunctionPair {
        let forward = FunctionSummary(
            name: "fwd",
            parameters: [Parameter(label: forwardLabel, internalName: "x", typeText: paramType, isInout: false)],
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "A.swift", line: 1, column: 1),
            containingTypeName: "TypeA",
            bodySignals: .empty
        )
        let reverse = FunctionSummary(
            name: "rev",
            parameters: [Parameter(label: reverseLabel, internalName: "x", typeText: returnType, isInout: false)],
            returnTypeText: paramType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "B.swift", line: 5, column: 1),
            containingTypeName: "TypeB",
            bodySignals: .empty
        )
        return FunctionPair(forward: forward, reverse: reverse)
    }
}
