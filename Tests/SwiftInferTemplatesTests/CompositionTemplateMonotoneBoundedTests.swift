import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// V1.21.B / **V1.29.C** — monotone-bounded label gate on
/// `CompositionTemplate`. Labels like `until:`, `to:`, `at:` signal
/// monotone-bounded semantics (`op(s, a).op(s, b) == max(a, b)`-bounded),
/// not additive composition (`op(s, a).op(s, b) == op(s, a + b)`).
///
/// V1.21.B introduced a -25 counter (Strong → Likely demote). **V1.29.C
/// promotes the counter to a full Signal.vetoWeight veto** per the
/// cycle-25 4-cycle-stable-reject finding on `advance(until:)` (cycles
/// 17 + 20 + 23 + 25 all measured REJECT).
@Suite("CompositionTemplate — V1.29.C monotone-bounded label full veto")
struct CompositionTemplateMonotoneBoundedTests {

    // MARK: - Helpers

    private func valueSemanticResolver(carrier: String = "BucketIterator") -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: carrier,
                kind: .struct,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "index", typeName: "Int")]
            )
        ])
    }

    private func liftedAdvance(
        paramLabel: String?,
        carrier: String = "BucketIterator"
    ) -> LiftedTransformation {
        let summary = FunctionSummary(
            name: "advance",
            parameters: [
                Parameter(
                    label: paramLabel,
                    internalName: "target",
                    typeText: "Int",
                    isInout: false
                )
            ],
            returnTypeText: "Void",
            isThrows: false,
            isAsync: false,
            isMutating: true,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: carrier,
            bodySignals: .empty
        )
        return LiftedTransformation.lift(
            summary,
            carrierKindResolver: valueSemanticResolver(carrier: carrier)
        )!
    }

    // MARK: - V1.29.C — veto fires on each curated label

    @Test("V1.29.C — 'advance(until: Int)' fires full veto (Suppressed)")
    func untilLabelFiresVeto() {
        let suggestion = CompositionTemplate.suggest(
            forLifted: liftedAdvance(paramLabel: "until"),
            carrierKindResolver: valueSemanticResolver()
        )
        #expect(suggestion == nil, "monotone-bounded 'until' should fire full veto (Suppressed)")
    }

    @Test("V1.29.C — all curated labels fire full veto (until, to, at, upTo, before, through)")
    func allCuratedLabelsFireVeto() {
        for label in CompositionTemplate.monotoneBoundedLabels {
            let suggestion = CompositionTemplate.suggest(
                forLifted: liftedAdvance(paramLabel: label),
                carrierKindResolver: valueSemanticResolver()
            )
            #expect(
                suggestion == nil,
                "Label '\(label)' should fire full veto (Suppressed); got non-nil"
            )
        }
    }

    // MARK: - Veto does NOT fire on non-curated labels

    @Test("Additive 'by:' label preserves Strong (no veto)")
    func byLabelPreservesStrong() throws {
        let suggestion = try #require(CompositionTemplate.suggest(
            forLifted: liftedAdvance(paramLabel: "by"),
            carrierKindResolver: valueSemanticResolver()
        ))
        // 30 + 40 + 5 + 10 = 85 → Strong (no veto). 'by:' is the canonical
        // additive label and is deliberately excluded from the curated set.
        #expect(suggestion.score.total == 85)
        #expect(suggestion.score.tier == .strong)
    }

    @Test("Unlabeled parameter (`_`) does not fire monotone-bounded veto")
    func unlabeledParamPreservesStrong() throws {
        let suggestion = try #require(CompositionTemplate.suggest(
            forLifted: liftedAdvance(paramLabel: nil),
            carrierKindResolver: valueSemanticResolver()
        ))
        #expect(suggestion.score.total == 85)
    }

    @Test("Non-curated label (e.g., 'amount') does not fire veto")
    func nonCuratedLabelPreservesStrong() throws {
        let suggestion = try #require(CompositionTemplate.suggest(
            forLifted: liftedAdvance(paramLabel: "amount"),
            carrierKindResolver: valueSemanticResolver()
        ))
        #expect(suggestion.score.total == 85)
    }

    // MARK: - Cycle-17 / cycle-25 BucketIterator.advance(until:) end-to-end

    @Test("V1.29.C — cycle-25 #36 BucketIterator.advance(until:) is now Suppressed")
    func cycle25BucketIteratorEndToEnd() {
        // Reproduces the cycle-25 V1.28.C pick #36: lifted form
        // (BucketIterator, Int) -> BucketIterator on `advance(until:)`.
        // V1.21.B previously demoted Strong (85) → Likely (60); V1.29.C
        // now suppresses outright (full veto). 4-cycle-stable-reject
        // (cycles 17 + 20 + 23 + 25) justifies the promotion.
        let suggestion = CompositionTemplate.suggest(
            forLifted: liftedAdvance(paramLabel: "until", carrier: "BucketIterator"),
            carrierKindResolver: valueSemanticResolver(carrier: "BucketIterator")
        )
        #expect(suggestion == nil)
    }
}
