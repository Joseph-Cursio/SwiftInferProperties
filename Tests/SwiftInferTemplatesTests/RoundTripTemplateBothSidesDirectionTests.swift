import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// V1.22.B — both-sides direction-label full-veto extension on V1.12.1's
/// `RoundTripTemplate.directionLabelCounterSignal(for:)`. Direct cycle-18
/// finding closure: extends the cycle-9 V1.12.1 -15 magnitude (either-
/// side fires) to -25 (full veto-equivalent) when **both** pair sides
/// have first-parameter labels in `DirectionLabels.curated`.
///
/// Score arithmetic at v1.21:
/// - bare typeSymmetry (+30) + carrier (+5) - 15 = +20 (Possible boundary;
///   surfaces under --include-possible)
/// - bare typeSymmetry (+30) + carrier (+5) - 25 (V1.22.B) = +10 (Suppressed;
///   filtered from --include-possible)
@Suite("RoundTripTemplate — V1.22.B both-sides direction-label full-veto")
struct RoundTripTemplateBothSidesDirectionTests {

    private func directionPair(
        forward: String = "index",
        forwardLabel: String?,
        reverse: String = "index",
        reverseLabel: String?,
        type: String = "Int"
    ) -> FunctionPair {
        let forwardSummary = FunctionSummary(
            name: forward,
            parameters: [Parameter(label: forwardLabel, internalName: "x", typeText: type, isInout: false)],
            returnTypeText: type,
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: "OrderedSet",
            bodySignals: .empty
        )
        let reverseSummary = FunctionSummary(
            name: reverse,
            parameters: [Parameter(label: reverseLabel, internalName: "x", typeText: type, isInout: false)],
            returnTypeText: type,
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 5, column: 1),
            containingTypeName: "OrderedSet",
            bodySignals: .empty
        )
        return FunctionPair(forward: forwardSummary, reverse: reverseSummary)
    }

    // MARK: - Both-sides direction-labeled fires at -25

    @Test("'after' / 'before' both-sides direction-labeled fires -25 veto (cycle-18 case)")
    func indexAfterBeforeFiresMinus25() throws {
        let signal = RoundTripTemplate.directionLabelCounterSignal(
            for: directionPair(forwardLabel: "after", reverseLabel: "before")
        )
        let veto = try #require(signal)
        #expect(veto.weight == -25)
        #expect(veto.detail.contains("Both pair sides direction-labeled"))
        #expect(veto.detail.contains("after"))
        #expect(veto.detail.contains("before"))
    }

    @Test("'next' / 'previous' both-sides fires -25")
    func nextPrevFiresMinus25() {
        let signal = RoundTripTemplate.directionLabelCounterSignal(
            for: directionPair(forwardLabel: "next", reverseLabel: "previous")
        )
        #expect(signal?.weight == -25)
    }

    @Test("Same direction label on both sides ('after' / 'after') fires -25")
    func sameLabelBothSidesFiresMinus25() {
        let signal = RoundTripTemplate.directionLabelCounterSignal(
            for: directionPair(forwardLabel: "after", reverseLabel: "after")
        )
        #expect(signal?.weight == -25)
    }

    // MARK: - Single-side direction-labeled preserves V1.12.1 -15

    @Test("Single-side direction-labeled preserves V1.12.1 -15 magnitude")
    func singleSidePreservesMinus15() throws {
        let signal = RoundTripTemplate.directionLabelCounterSignal(
            for: directionPair(forwardLabel: "after", reverseLabel: nil)
        )
        let counter = try #require(signal)
        #expect(counter.weight == -15)
        #expect(counter.detail.contains("Direction-label argument"))
        // Single-side detail string format preserved exactly (cycle-9
        // V1.12.1 wording carries forward to maintain rate-stability on
        // existing single-side picks).
    }

    @Test("Reverse-only direction-labeled preserves V1.12.1 -15")
    func reverseOnlyPreservesMinus15() {
        let signal = RoundTripTemplate.directionLabelCounterSignal(
            for: directionPair(forwardLabel: nil, reverseLabel: "before")
        )
        #expect(signal?.weight == -15)
    }

    @Test("Asymmetric direction-pair (cycle-18 cross-pair noise: 'after' / 'forScale') preserves V1.12.1 -15")
    func asymmetricCrossPairPreservesMinus15() {
        // 'forScale' is in DomainMarkerLabels.curated, NOT in
        // DirectionLabels.curated. So only 'after' is direction-labeled,
        // single-side path fires.
        let signal = RoundTripTemplate.directionLabelCounterSignal(
            for: directionPair(forwardLabel: "after", reverseLabel: "forScale")
        )
        #expect(signal?.weight == -15)
    }

    // MARK: - No direction labels: no signal

    @Test("Neither side direction-labeled returns nil")
    func neitherSideNoSignal() {
        let signal = RoundTripTemplate.directionLabelCounterSignal(
            for: directionPair(forwardLabel: "encode", reverseLabel: "decode")
        )
        #expect(signal == nil)
    }

    @Test("Both sides nil-labeled returns nil")
    func bothNilNoSignal() {
        let signal = RoundTripTemplate.directionLabelCounterSignal(
            for: directionPair(forwardLabel: nil, reverseLabel: nil)
        )
        #expect(signal == nil)
    }

    // MARK: - End-to-end suggest()

    @Test("End-to-end: index(after:) × index(before:) Int round-trip is suppressed at v1.22")
    func endToEndIndexAfterBeforeSuppressed() {
        let suggestion = RoundTripTemplate.suggest(
            for: directionPair(forwardLabel: "after", reverseLabel: "before")
        )
        // 30 typeSymmetry - 25 V1.22.B = +5 → Suppressed; filtered from
        // --include-possible. (The carrier signal would push to +10
        // if a CarrierKindResolver were threaded, but the unit test
        // doesn't supply one — the calling production code does, in
        // which case the score becomes +10 = Suppressed boundary.)
        #expect(suggestion == nil, "Both-sides direction-labeled should suppress at v1.22.B")
    }

    @Test("End-to-end: asymmetric pair fires V1.12.1 single-side -15 (not V1.22.B -25)")
    func endToEndAsymmetricFiresSingleSideOnly() {
        // Cycle-18 finding: cross-pair noise where one side is direction-
        // labeled and the other is domain-marker-labeled fires V1.12.1's
        // single-side -15 path (NOT V1.22.B's -25 path). V1.22.B is
        // intentionally narrow — closes truly-symmetric direction-pairs
        // only; cross-pair noise is a separate v1.23+ mechanism class.
        // Asserted at the signal level (rather than end-to-end suggest
        // null/non-null) because the score arithmetic without a
        // CarrierKindResolver puts the score at the Suppressed boundary;
        // in production the resolver +5 lifts the score to +20 = Possible.
        let signal = RoundTripTemplate.directionLabelCounterSignal(
            for: directionPair(
                forward: "index",
                forwardLabel: "after",
                reverse: "_minimumCapacity",
                reverseLabel: "forScale",
                type: "Int"
            )
        )
        #expect(signal?.weight == -15, "Asymmetric pair must fire V1.12.1 single-side, not V1.22.B both-sides")
    }
}
