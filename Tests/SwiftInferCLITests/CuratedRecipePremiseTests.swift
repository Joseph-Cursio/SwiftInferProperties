import PropertyLawCore
@testable import SwiftInferCLI
import Testing

/// The two curated recipe tables in `resolveRecipe` **short-circuit before the
/// kit-side call**, and each states a premise about a package this repo does not
/// own: `StrategistDispatchEmitter+OCRecipes` says its carriers are ones
/// *"`DerivationStrategist.strategy(for:)` returns `.todo` on"*, and
/// `+SyntaxRecipes` says syntax nodes are *"external types with no indexed
/// shape, so the strategist would return `.todo`"*.
///
/// Both premises were asserted when the tables were written (V1.59.A / V1.69.B)
/// and **nothing rechecked them since**. That is the failure shape this repo has
/// already paid for twice — `KitCoverageDriftTests` passed green through 13
/// false coverage claims, and `AssumedKitCoverageTests` pinned a suppression as
/// correct while the law it deferred to did not exist. A claim about a sibling
/// package needs a guard that can actually see the sibling.
///
/// The exposure is live rather than theoretical: SwiftPropertyLaws ships
/// hand-written generators for three of the eight OC carriers in its opt-in
/// `PropertyLawCollections` product, so the kit is already moving on this
/// surface. If it ever teaches `composedGenerator` an OC spelling, the curated
/// entry silently wins and the kit's version is never reached.
///
/// **Measured 2026-08-08 at kit `3.27.1` (`595e400`): 0 of 25 carriers derive.**
/// Every curated entry is doing necessary work; there is no dead entry to
/// remove. This suite pins that, so the day it stops being true is a test
/// failure rather than a silent shadowing.
///
/// ## Why the control test is not decoration
///
/// A probe that answers `nil` to everything makes this whole suite green and
/// useless — the arm-4 trap from `docs/measurements/stale-summary-guard-declined.md`,
/// and the same reason `DeferralFalsifierTests` asserts its resolver rejects a
/// fake symbol as well as finding a real one. So the controls assert the kit
/// *does* derive the shapes it documents, and the population is asserted
/// non-empty: a scan narrowed to nothing passes, and that is this repo's
/// confident zero.
@Suite("Curated recipe tables — the kit still derives none of them")
struct CuratedRecipePremiseTests {

    private typealias Emitter = StrategistDispatchEmitter

    /// Composite spellings `CompositeMemberParser` documents itself as
    /// composing: `T?` → `.optional`, `[T]` → `.array(of:)`, `[K: V]` →
    /// `zip(...).dictionary(ofAtMost:)`, `Set<T>` → `.set(ofAtMost:)`, and
    /// recursion on element types.
    private static let derivableControls = [
        "[Int]",
        "Int?",
        "[String: Int]",
        "Set<Int>",
        "[Int?]"
    ]

    private static let curatedCarriers =
        Emitter.curatedOCRecipeCarriers + Emitter.curatedSyntaxRecipeCarriers

    @Test("the guarded population is non-empty")
    func populationIsNotEmpty() {
        #expect(
            !Emitter.curatedOCRecipeCarriers.isEmpty,
            "The OC table is empty, so the per-carrier premise check quantifies over nothing."
        )
        #expect(
            !Emitter.curatedSyntaxRecipeCarriers.isEmpty,
            "The syntax table is empty, so the per-carrier premise check quantifies over nothing."
        )
    }

    @Test(
        "the kit derives the control shapes — so a blanket nil cannot pass this suite",
        arguments: derivableControls
    )
    func kitDerivesControlShapes(carrier: String) {
        #expect(
            DerivationStrategist.composedGenerator(forTypeName: carrier) != nil,
            """
            The kit failed to derive \(carrier), a shape `CompositeMemberParser` documents \
            itself as composing. Fix this before believing the per-carrier results below: a \
            `composedGenerator` that answers nil to everything would report every curated \
            entry as still-necessary regardless of the truth.
            """
        )
    }

    @Test(
        "the kit derives no carrier the curated tables short-circuit",
        arguments: curatedCarriers
    )
    func kitDoesNotDeriveCuratedCarrier(carrier: String) {
        let composed = DerivationStrategist.composedGenerator(forTypeName: carrier)
        #expect(
            composed == nil,
            """
            The kit now derives a generator for \(carrier), which the curated table \
            short-circuits before ever asking it:

                \(composed?.expression ?? "<nil>")

            The premise the table was written under no longer holds. Decide which generator \
            should win — the kit's derivation or the curated entry — and record why. Deleting \
            the curated entry is the default; keeping it needs a stated reason, because a \
            curated entry that outranks a kit derivation is invisible to every downstream \
            consumer and to `make dead-code` (the file stays live, only the entry is dead).
            """
        )
    }
}
