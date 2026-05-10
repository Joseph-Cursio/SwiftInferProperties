import PropertyLawCore
import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

/// V1.21.B — monotone-bounded label counter on `CompositionTemplate`.
/// Direct cycle-17 finding closure (1/1 reject on `BucketIterator.advance(until: Int)`):
/// labels like `until:`, `to:`, `at:` signal monotone-bounded semantics
/// (`op(s, a).op(s, b) == max(a, b)`-bounded), not additive composition
/// (`op(s, a).op(s, b) == op(s, a + b)`). Demotes Strong → Likely (-25
/// counter, not full veto) so the calibration record is preserved at
/// small-n.
@Suite("CompositionTemplate — V1.21.B monotone-bounded label counter")
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

    // MARK: - Veto fires on each curated label

    @Test("'advance(until: Int)' demotes 85 → 60 (Strong → Likely)")
    func untilLabelDemotes() throws {
        let suggestion = try #require(CompositionTemplate.suggest(
            forLifted: liftedAdvance(paramLabel: "until"),
            carrierKindResolver: valueSemanticResolver()
        ))
        // 30 type-shape + 40 curated verb 'advance' + 5 carrier + 10 lift
        // - 25 monotone-bounded = 60 → Likely (not Suppressed).
        #expect(suggestion.score.total == 60)
        #expect(suggestion.score.tier == .likely)
        // Detail string mentions monotone-bounded rationale.
        let monotoneSignal = suggestion.explainability.whySuggested.first(where: {
            $0.contains("Monotone-bounded")
        })
        #expect(monotoneSignal != nil, "monotone-bounded counter should appear in whySuggested")
    }

    @Test("All curated labels demote (until, to, at, upTo, before, through)")
    func allCuratedLabelsDemote() {
        for label in CompositionTemplate.monotoneBoundedLabels {
            let suggestion = CompositionTemplate.suggest(
                forLifted: liftedAdvance(paramLabel: label),
                carrierKindResolver: valueSemanticResolver()
            )
            let result = try! #require(suggestion, "Expected suggestion for label '\(label)'")
            #expect(
                result.score.total == 60,
                "Label '\(label)' should demote to 60; got \(result.score.total)"
            )
            #expect(result.score.tier == .likely)
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

    @Test("Unlabeled parameter (`_`) does not fire monotone-bounded counter")
    func unlabeledParamPreservesStrong() throws {
        let suggestion = try #require(CompositionTemplate.suggest(
            forLifted: liftedAdvance(paramLabel: nil),
            carrierKindResolver: valueSemanticResolver()
        ))
        #expect(suggestion.score.total == 85)
    }

    @Test("Non-curated label (e.g., 'amount') does not fire counter")
    func nonCuratedLabelPreservesStrong() throws {
        let suggestion = try #require(CompositionTemplate.suggest(
            forLifted: liftedAdvance(paramLabel: "amount"),
            carrierKindResolver: valueSemanticResolver()
        ))
        #expect(suggestion.score.total == 85)
    }

    // MARK: - Cycle-17 BucketIterator.advance(until:) end-to-end

    @Test("Cycle-17 BucketIterator.advance(until: Int) demotes from Strong to Likely")
    func cycle17BucketIteratorEndToEnd() throws {
        // Reproduces the cycle-17 V1.20.C pick #46: lifted form
        // (BucketIterator, Int) -> BucketIterator on `advance(until:)`.
        // V1.21.B demotes the score from 85 (Strong, default-visible) to
        // 60 (Likely, default-visible-but-cycle-17-rejected).
        let suggestion = try #require(CompositionTemplate.suggest(
            forLifted: liftedAdvance(paramLabel: "until", carrier: "BucketIterator"),
            carrierKindResolver: valueSemanticResolver(carrier: "BucketIterator")
        ))
        #expect(suggestion.score.total == 60)
        #expect(suggestion.score.tier == .likely)
        #expect(suggestion.templateName == "composition")
    }
}
