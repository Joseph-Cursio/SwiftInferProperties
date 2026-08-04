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

    /// NB the arithmetic. A bare synthetic summary scores **30** (type symmetry
    /// alone); the real-corpus floor is **35**, because a value-semantic carrier
    /// adds +5 — the band the 2026-08-04 survey measured 13 false laws in.
    @Test("@Idempotent lifts a shape-only candidate out of hiding (30 → 45)")
    func declaredIdempotentPromotes() {
        let bare = makeIdempotenceSummary(name: "process", paramType: "String", returnType: "String")
        let annotated = makeIdempotenceSummary(
            name: "process",
            paramType: "String",
            returnType: "String",
            declaredEffect: .idempotent
        )
        #expect(IdempotenceTemplate.suggest(for: bare)?.score.tier == .possible)

        let promoted = IdempotenceTemplate.suggest(for: annotated)
        #expect(promoted?.score.total == 45)
        #expect(promoted?.score.tier == .likely)
    }

    /// **The weight is deliberately BELOW a curated verb, and that is the finding.**
    ///
    /// It shipped at +40 (verb parity) on the strength of SEI's paraphrase of the
    /// tier — "`f(f(x))` is semantically equivalent to `f(x)`". The OWNING package
    /// defines `@Idempotent` as "re-invocation with the same arguments produces the
    /// same observable result": `f(x)` twice, never `f` fed its own output. The
    /// annotation claims the adjacent property, so it cannot outrank a name that
    /// claims this one. If a future change raises it back to 40, this is the test
    /// that has to be argued with — and the argument has to address `quoted(_:)`,
    /// which satisfies the owner's definition and fails composition at trial 0.
    @Test("The declared claim scores BELOW a curated verb — it claims a weaker property")
    func weakerThanCuratedVerb() {
        let byName = makeIdempotenceSummary(name: "normalize", paramType: "String", returnType: "String")
        let byAnnotation = makeIdempotenceSummary(
            name: "process",
            paramType: "String",
            returnType: "String",
            declaredEffect: .idempotent
        )
        let nameScore = IdempotenceTemplate.suggest(for: byName)?.score.total
        let annotationScore = IdempotenceTemplate.suggest(for: byAnnotation)?.score.total
        #expect(nameScore == 70)
        #expect(annotationScore == 45)
        #expect((annotationScore ?? 0) < (nameScore ?? 0))
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
