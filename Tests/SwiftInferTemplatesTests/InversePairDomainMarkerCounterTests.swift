import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// V1.15.1 — domain-marker counter-signal on InversePairTemplate.
// Defensive scaffold: post-v1.14 OC inverse-pair surface is at 0
// (the V1.14.1 SetAlgebra-shape veto cleared the 6 pre-cycle-11
// candidates; no domain-marker candidates remain on any cycle-1...11
// corpus). Wired for symmetry with idempotence + round-trip and
// future-proofing.
//
// Score arithmetic for inverse-pair (baseline +25 typeSymmetry):
//   bare typeSymmetry            : +25  → Possible
//   bare + domain-marker counter : +25 - 15 = +10 → Suppressed
//   curated name (+10) + counter : +25 + 10 - 15 = +20 → boundary
//   direction (-10) + counter    : +25 - 10 - 15 = 0 → Suppressed

@Suite("InversePairTemplate — V1.15.1 domain-marker counter-signal")
struct InversePairDomainMarkerCounterTests {

    // MARK: - Suppression cases

    @Test("V1.15.1 — `forScale: ↔ forCapacity:` Self-typed pair is suppressed")
    func crossDomainSelfPairSuppressed() {
        // Hypothetical: future Self-typed binary op pair with explicit
        // domain markers (no real candidates on cycle-1..11 corpora).
        let pair = makePair(
            forwardName: "scaleA", forwardLabel: "forScale",
            reverseName: "scaleB", reverseLabel: "forCapacity",
            paramType: "Int", returnType: "Int"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion == nil, "Both-sides domain-marker pair should be suppressed")
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
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion == nil, "\(forward) ↔ \(reverse) should suppress")
    }

    // MARK: - Non-suppression cases

    @Test("V1.15.1 — asymmetric `forBucketContents:` ↔ `for:` preserved")
    func asymmetricForLabelPairPreserved() {
        let pair = makePair(
            forwardName: "_value", forwardLabel: "forBucketContents",
            reverseName: "_bucketContents", reverseLabel: "for",
            paramType: "UInt64", returnType: "UInt64"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        let hasDomainMarker = suggestion?.score.signals.contains { signal in
            signal.detail.contains("Domain-marker")
        } ?? false
        #expect(!hasDomainMarker, "One-side-labeled pair should not trigger counter")
    }

    @Test("V1.15.1 — non-domain labels do NOT trigger counter")
    func nonDomainLabelsDoNotTrigger() {
        let pair = makePair(
            forwardName: "fwd", forwardLabel: "value",
            reverseName: "rev", reverseLabel: "input",
            paramType: "Int", returnType: "Int"
        )
        let signal = InversePairTemplate.domainMarkerCounterSignal(for: pair)
        #expect(signal == nil)
    }

    // MARK: - Boundary + composition cases

    @Test("V1.15.1 — counter weight is exactly -15 (uniform across three templates)")
    func counterWeightIsMinusFifteen() {
        let pair = makePair(
            forwardName: "fwd", forwardLabel: "forScale",
            reverseName: "rev", reverseLabel: "forCapacity",
            paramType: "Int", returnType: "Int"
        )
        let signal = InversePairTemplate.domainMarkerCounterSignal(for: pair)
        #expect(signal?.weight == -15)
        #expect(signal?.kind == .directionLabel)
    }

    @Test("V1.15.1 — direction-label counter + domain-marker counter compose correctly")
    func directionAndDomainMarkerCompose() {
        // Hypothetical: a pair with direction-labeled forward and
        // domain-marked reverse. Direction counter (-10) fires on
        // either-side detection; domain-marker counter (-15) needs
        // both-sides — so this case fires direction only, not domain
        // marker. typeSymmetry +25 + direction -10 = +15 → Suppressed.
        let pair = makePair(
            forwardName: "step", forwardLabel: "after",
            reverseName: "scale", reverseLabel: "forCapacity",
            paramType: "Int", returnType: "Int"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion == nil)
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
}
