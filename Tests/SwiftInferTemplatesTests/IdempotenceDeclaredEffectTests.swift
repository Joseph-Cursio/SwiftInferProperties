import SwiftEffectInference
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Step 1 of the item-17 vocabulary work: swift-infer READS SwiftIdempotency's
/// effect vocabulary. These pin the four decisions that were arguable, not the
/// plumbing — the plumbing is one field and a `switch`.
@Suite("IdempotenceTemplate — author-declared effect")
struct IdempotenceDeclaredEffectTests {

    // MARK: - The claim corroborates

    /// NB the arithmetic, because it is easy to misquote. A bare synthetic
    /// summary scores **30** (type symmetry alone) and lands at `Likely` 70. The
    /// real-corpus floor is **35**, because a value-semantic carrier adds +5 —
    /// that is the band the 2026-08-04 survey measured 13 false laws in — and
    /// there the same +40 reaches **75**, exactly `Tier.strong`'s floor. Both are
    /// true; only the second is the one to quote about real code.
    @Test("@Idempotent takes a shape-only candidate from Possible to Likely (30 → 70)")
    func declaredIdempotentPromotes() {
        let bare = makeIdempotenceSummary(name: "process", paramType: "String", returnType: "String")
        let annotated = makeIdempotenceSummary(
            name: "process",
            paramType: "String",
            returnType: "String",
            declaredEffect: .idempotent
        )
        // The unannotated control is the score-35 floor this whole afternoon's
        // false-positive survey lives at (13 of 55 executed rows were false).
        #expect(IdempotenceTemplate.suggest(for: bare)?.score.tier == .possible)

        let promoted = IdempotenceTemplate.suggest(for: annotated)
        #expect(promoted?.score.total == 70)
        #expect(promoted?.score.tier == .likely)
    }

    @Test("The declared claim is worth exactly as much as a curated verb, and no more")
    func parityWithCuratedVerb() {
        let byName = makeIdempotenceSummary(name: "normalize", paramType: "String", returnType: "String")
        let byAnnotation = makeIdempotenceSummary(
            name: "process",
            paramType: "String",
            returnType: "String",
            declaredEffect: .idempotent
        )
        // Both are "the author told us" — one by naming, one by annotating. If a
        // future change makes an annotation outrank a name, this is the test that
        // should have to be argued with first.
        #expect(
            IdempotenceTemplate.suggest(for: byName)?.score.total
                == IdempotenceTemplate.suggest(for: byAnnotation)?.score.total
        )
    }

    // MARK: - The denial vetoes

    @Test("@NonIdempotent suppresses the suggestion entirely")
    func declaredNonIdempotentVetoes() {
        let summary = makeIdempotenceSummary(
            name: "normalize",                       // curated verb, +40 — still vetoed
            paramType: "String",
            returnType: "String",
            declaredEffect: .nonIdempotent
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }

    @Test("@ExternallyIdempotent vetoes — the UNCONDITIONAL law is what's false")
    func externallyIdempotentVetoes() {
        // Idempotent only when routed through a dedup key, so `f(f(x)) == f(x)`
        // as this template emits it is false as written. The tier this repo had
        // no way to express before reading the vocabulary.
        for key in [String?.some("requestID"), nil] {
            let summary = makeIdempotenceSummary(
                name: "charge",
                paramType: "Payment",
                returnType: "Payment",
                declaredEffect: .externallyIdempotent(keyParameter: key)
            )
            #expect(IdempotenceTemplate.suggest(for: summary) == nil)
        }
    }

    // MARK: - The tiers that must stay silent

    @Test("@Observational and @Pure move the score in NEITHER direction")
    func orthogonalTiersAreSilent() {
        let bare = makeIdempotenceSummary(name: "process", paramType: "String", returnType: "String")
        let baseline = IdempotenceTemplate.suggest(for: bare)?.score.total

        for effect in [Effect.observational, .pure] {
            let summary = makeIdempotenceSummary(
                name: "process",
                paramType: "String",
                returnType: "String",
                declaredEffect: effect
            )
            let suggestion = IdempotenceTemplate.suggest(for: summary)
            // `observational` is retry-safe BY DEFINITION (it logs or reads
            // without affecting program semantics) and `pure` is orthogonal —
            // `x + 1` is pure and not idempotent. Neither implies the law and
            // neither denies it, so silence is the correct claim. An earlier
            // draft of this work listed `@Observational` as a veto; it was wrong.
            #expect(suggestion != nil)
            #expect(suggestion?.score.total == baseline)
        }
    }

    @Test("No annotation changes nothing — the overwhelmingly common case")
    func absentClaimIsInert() {
        let summary = makeIdempotenceSummary(name: "process", paramType: "String", returnType: "String")
        #expect(summary.declaredEffect == nil)
        #expect(IdempotenceTemplate.declaredEffectSignal(for: summary) == nil)
    }

    // MARK: - Corroborate-only

    @Test("An annotation cannot surface a law the SHAPE did not match")
    func cannotSurfaceOnAnnotationAlone() {
        // `String -> Int` is not `T -> T`, so `appliesTo` rejects it. The claim
        // is real and the template still declines: this signal raises a
        // shape-matched candidate, it never conjures one.
        let summary = makeIdempotenceSummary(
            name: "process",
            paramType: "String",
            returnType: "Int",
            declaredEffect: .idempotent
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }
}
