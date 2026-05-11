import PropertyLawCore
import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

/// V1.24.A — asymmetric label class mismatch counter on
/// `RoundTripTemplate`. Direct cycle-19 finding + cycle-20 reconfirmed
/// at 5/5 = 100% reject on OC `index(after:) × _minimumCapacity(forScale:)`-
/// shape pairs.
@Suite("RoundTripTemplate — V1.24.A asymmetric label class mismatch counter")
struct RoundTripAsymmetricLabelCounterTests {

    private func pair(
        forwardName: String,
        forwardLabel: String?,
        reverseName: String,
        reverseLabel: String?
    ) -> FunctionPair {
        let f = FunctionSummary(
            name: forwardName,
            parameters: [Parameter(label: forwardLabel, internalName: "x", typeText: "Int", isInout: false)],
            returnTypeText: "Int",
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: "OrderedSet",
            bodySignals: .empty
        )
        let r = FunctionSummary(
            name: reverseName,
            parameters: [Parameter(label: reverseLabel, internalName: "x", typeText: "Int", isInout: false)],
            returnTypeText: "Int",
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 5, column: 1),
            containingTypeName: "OrderedSet",
            bodySignals: .empty
        )
        return FunctionPair(forward: f, reverse: r)
    }

    // MARK: - Asymmetric fires -25 (both orientations)

    @Test("'after:' (direction) × 'forScale:' (domain-marker) fires -25 (cycle-19/20 case)")
    func directionThenDomainFires() {
        let signal = RoundTripTemplate.asymmetricLabelClassMismatchCounterSignal(
            for: pair(
                forwardName: "index", forwardLabel: "after",
                reverseName: "_minimumCapacity", reverseLabel: "forScale"
            )
        )
        let veto = try! #require(signal)
        #expect(veto.weight == -25)
        #expect(veto.detail.contains("Asymmetric label class mismatch"))
        #expect(veto.detail.contains("after"))
        #expect(veto.detail.contains("forScale"))
    }

    @Test("'forScale:' (domain-marker) × 'after:' (direction) fires -25 (reverse orientation)")
    func domainThenDirectionFires() {
        let signal = RoundTripTemplate.asymmetricLabelClassMismatchCounterSignal(
            for: pair(
                forwardName: "_minimumCapacity", forwardLabel: "forScale",
                reverseName: "index", reverseLabel: "after"
            )
        )
        #expect(signal?.weight == -25)
    }

    @Test("'before:' × 'forCapacity:' fires -25")
    func differentDirectionAndDomainFires() {
        let signal = RoundTripTemplate.asymmetricLabelClassMismatchCounterSignal(
            for: pair(
                forwardName: "index", forwardLabel: "before",
                reverseName: "_scale", reverseLabel: "forCapacity"
            )
        )
        #expect(signal?.weight == -25)
    }

    // MARK: - Symmetric (both same class) does NOT fire

    @Test("Both direction-labeled ('after' / 'before') does NOT fire — V1.22.B territory")
    func bothDirectionDoesNotFire() {
        let signal = RoundTripTemplate.asymmetricLabelClassMismatchCounterSignal(
            for: pair(
                forwardName: "index", forwardLabel: "after",
                reverseName: "index", reverseLabel: "before"
            )
        )
        #expect(signal == nil, "Both-direction case is V1.22.B's territory, not V1.24.A")
    }

    @Test("Both domain-marker-labeled ('forScale' / 'forCapacity') does NOT fire — V1.15.1 territory")
    func bothDomainDoesNotFire() {
        let signal = RoundTripTemplate.asymmetricLabelClassMismatchCounterSignal(
            for: pair(
                forwardName: "_minimumCapacity", forwardLabel: "forScale",
                reverseName: "_scale", reverseLabel: "forCapacity"
            )
        )
        #expect(signal == nil, "Both-domain case is V1.15.1's territory, not V1.24.A")
    }

    // MARK: - No-label / non-curated cases do NOT fire

    @Test("Neither side labeled returns nil")
    func neitherLabeledReturnsNil() {
        let signal = RoundTripTemplate.asymmetricLabelClassMismatchCounterSignal(
            for: pair(
                forwardName: "encode", forwardLabel: nil,
                reverseName: "decode", reverseLabel: nil
            )
        )
        #expect(signal == nil)
    }

    @Test("Direction × non-curated label returns nil")
    func directionAndNonCuratedReturnsNil() {
        let signal = RoundTripTemplate.asymmetricLabelClassMismatchCounterSignal(
            for: pair(
                forwardName: "index", forwardLabel: "after",
                reverseName: "lookup", reverseLabel: "key"
            )
        )
        #expect(signal == nil, "Non-curated reverse label doesn't trigger asymmetric")
    }

    // MARK: - End-to-end suggest()

    @Test("End-to-end: 'index(after:) × _minimumCapacity(forScale:)' suppressed (cycle-19 finding)")
    func endToEndAsymmetricSuppressed() {
        // 30 typeSymmetry - 15 V1.12.1 single-side direction - 25 V1.24.A
        // asymmetric = -10 → Suppressed.
        let suggestion = RoundTripTemplate.suggest(
            for: pair(
                forwardName: "index", forwardLabel: "after",
                reverseName: "_minimumCapacity", reverseLabel: "forScale"
            )
        )
        #expect(suggestion == nil, "V1.24.A should suppress the cycle-19 asymmetric class")
    }
}
