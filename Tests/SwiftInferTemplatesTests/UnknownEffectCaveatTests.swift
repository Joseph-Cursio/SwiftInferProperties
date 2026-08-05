import SwiftEffectInference
import SwiftInferCore
import Testing

@testable import SwiftInferTemplates

/// Link 3 of the `@EffectUnknown` chain: swift-infer acts on the marker.
///
/// The whole point of the marker is that *"I cannot determine this"* should stop
/// being indistinguishable from *"the author said nothing"*. These tests pin the
/// distinction at both ends — the line appears, and **the score does not move** —
/// because getting the second half wrong is the easy mistake here.
@Suite("@EffectUnknown — a line, not points")
struct UnknownEffectCaveatTests {

    private func summary(
        declaresUnknownEffect: Bool,
        declaredEffect: Effect? = nil
    ) -> FunctionSummary {
        makeIdempotenceSummary(
            name: "normalize",
            paramType: "String",
            returnType: "String",
            containingType: "Fixture",
            declaredEffect: declaredEffect,
            declaresUnknownEffect: declaresUnknownEffect
        )
    }

    @Test("the caveat appears when the author declared the effect unknown")
    func caveatAppearsWhenDeclared() {
        let caveats = IdempotenceTemplate.makeCaveats(
            for: summary(declaresUnknownEffect: true)
        )
        #expect(caveats.contains(IdempotenceTemplate.unknownEffectCaveat))
    }

    @Test("no caveat when the author said nothing")
    func noCaveatWhenUnannotated() {
        let caveats = IdempotenceTemplate.makeCaveats(
            for: summary(declaresUnknownEffect: false)
        )
        #expect(!caveats.contains(IdempotenceTemplate.unknownEffectCaveat))
    }

    /// **The half most likely to be got wrong.** `@NonIdempotent` vetoes because
    /// it denies the law; `unknown` denies nothing, so it must not veto — and it
    /// must not corroborate either. Asserting the score is *identical* with and
    /// without the marker is the only way to pin "score-neutral"; asserting the
    /// caveat's presence would pass just as well if the weight had moved.
    @Test("the marker does not move the score in either direction")
    func markerIsScoreNeutral() {
        let withMarker = IdempotenceTemplate.accumulatedSignals(
            for: summary(declaresUnknownEffect: true),
            vocabulary: .empty,
            inheritedTypesByName: [:],
            carrierKindResolver: nil
        )
        let without = IdempotenceTemplate.accumulatedSignals(
            for: summary(declaresUnknownEffect: false),
            vocabulary: .empty,
            inheritedTypesByName: [:],
            carrierKindResolver: nil
        )
        let vetoed = withMarker.contains(where: \.isVeto)
        #expect(Score(signals: withMarker).total == Score(signals: without).total)
        #expect(vetoed == false)
    }

    /// The contrast that gives the marker its meaning, in one test: a declaration
    /// that *denies* the law still vetoes, so score-neutrality above is a property
    /// of `unknown` specifically and not of the template ignoring declarations.
    @Test("@NonIdempotent still vetoes — unknown is not a weaker form of it")
    func nonIdempotentStillVetoes() {
        let signals = IdempotenceTemplate.accumulatedSignals(
            for: summary(declaresUnknownEffect: false, declaredEffect: .nonIdempotent),
            vocabulary: .empty,
            inheritedTypesByName: [:],
            carrierKindResolver: nil
        )
        let vetoed = signals.contains(where: \.isVeto)
        #expect(vetoed)
    }
}
