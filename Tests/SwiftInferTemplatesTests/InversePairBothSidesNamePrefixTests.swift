import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// V1.27.B — name-prefix-gated both-sides direction-label full-veto on
/// InversePairTemplate. Direct cycle-23 finding closure: cycle-23 #26
/// `bucket(after:) × bucket(before:)` REJECT.
///
/// Mirrors V1.25.A pattern on idempotence + V1.22.B pattern on round-trip:
/// when both pair sides direction-labeled AND both names have curated
/// index-advance prefix (`index`/`bucket`/`word`), fire full veto.
@Suite("InversePairTemplate — V1.27.B both-sides direction + name-prefix veto")
struct InversePairBothSidesNamePrefixTests {

    private func pair(
        forwardName: String,
        forwardLabel: String?,
        reverseName: String,
        reverseLabel: String?
    ) -> FunctionPair {
        let forwardSummary = FunctionSummary(
            name: forwardName,
            parameters: [Parameter(label: forwardLabel, internalName: "x", typeText: "Bucket", isInout: false)],
            returnTypeText: "Bucket",
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: "_HashTable.UnsafeHandle",
            bodySignals: .empty
        )
        let reverseSummary = FunctionSummary(
            name: reverseName,
            parameters: [Parameter(label: reverseLabel, internalName: "x", typeText: "Bucket", isInout: false)],
            returnTypeText: "Bucket",
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 5, column: 1),
            containingTypeName: "_HashTable.UnsafeHandle",
            bodySignals: .empty
        )
        return FunctionPair(forward: forwardSummary, reverse: reverseSummary)
    }

    @Test("'bucket(after:) × bucket(before:)' fires full veto (cycle-23 #26 case)")
    func bucketBothSidesFiresFullVeto() throws {
        let signal = InversePairTemplate.directionLabelCounterSignal(
            for: pair(forwardName: "bucket", forwardLabel: "after",
                      reverseName: "bucket", reverseLabel: "before")
        )
        let veto = try #require(signal)
        #expect(veto.isVeto)
        #expect(veto.detail.contains("name-prefix match"))
    }

    @Test("'word(after:) × word(before:)' fires full veto")
    func wordBothSidesFiresFullVeto() {
        let signal = InversePairTemplate.directionLabelCounterSignal(
            for: pair(forwardName: "word", forwardLabel: "after",
                      reverseName: "word", reverseLabel: "before")
        )
        #expect(signal?.isVeto == true)
    }

    @Test("'index(after:) × index(before:)' fires full veto")
    func indexBothSidesFiresFullVeto() {
        let signal = InversePairTemplate.directionLabelCounterSignal(
            for: pair(forwardName: "index", forwardLabel: "after",
                      reverseName: "index", reverseLabel: "before")
        )
        #expect(signal?.isVeto == true)
    }

    @Test("V1.29.A — asymmetric cursor × non-direction pair fires full veto")
    func asymmetricCursorFiresFullVeto() throws {
        // 'bucket(after:) × firstOccupiedBucketInChain(with:)': forward
        // side is cursor-advance (direction-prefix-name + direction-label),
        // reverse side is non-direction lookup. V1.29.A's asymmetric-pair
        // full-veto closes the cycle-25 #28 + #29 reject pattern.
        let signal = InversePairTemplate.directionLabelCounterSignal(
            for: pair(forwardName: "bucket", forwardLabel: "after",
                      reverseName: "firstOccupiedBucketInChain", reverseLabel: "with")
        )
        let veto = try #require(signal)
        #expect(veto.isVeto)
        #expect(veto.detail.contains("Asymmetric direction-pair"))
    }

    @Test("V1.29.A — asymmetric on reverse side also fires full veto")
    func asymmetricCursorOnReverseFiresFullVeto() {
        // 'firstOccupiedBucketInChain(with:) × bucket(before:)': reverse
        // side is the cursor-advance shape. Symmetric to the forward case.
        let signal = InversePairTemplate.directionLabelCounterSignal(
            for: pair(forwardName: "firstOccupiedBucketInChain", forwardLabel: "with",
                      reverseName: "bucket", reverseLabel: "before")
        )
        #expect(signal?.isVeto == true)
    }

    @Test("V1.29.A — asymmetric direction-label on non-cursor-prefix name preserves -10")
    func asymmetricNonCursorPreservesMinus10() {
        // 'transform(after:) × untransform(_:)': forward direction-labeled
        // but name doesn't match cursor-prefix list. V1.29.A's asymmetric
        // veto doesn't fire; falls through to V1.11.1 either-side -10.
        let signal = InversePairTemplate.directionLabelCounterSignal(
            for: pair(forwardName: "transform", forwardLabel: "after",
                      reverseName: "untransform", reverseLabel: nil)
        )
        #expect(signal?.weight == -10)
    }

    @Test("Both sides direction-labeled but non-index-advance name preserves -10")
    func bothDirectionNonPrefixPreservesMinus10() {
        // 'transform(after:) × untransform(before:)': both direction-
        // labeled but neither name has index/bucket/word prefix.
        // V1.27.B doesn't fire; falls through to either-side -10.
        let signal = InversePairTemplate.directionLabelCounterSignal(
            for: pair(forwardName: "transform", forwardLabel: "after",
                      reverseName: "untransform", reverseLabel: "before")
        )
        #expect(signal?.weight == -10)
    }

    @Test("Neither side labeled returns nil")
    func neitherLabeledReturnsNil() {
        let signal = InversePairTemplate.directionLabelCounterSignal(
            for: pair(forwardName: "encode", forwardLabel: nil,
                      reverseName: "decode", reverseLabel: nil)
        )
        #expect(signal == nil)
    }
}
