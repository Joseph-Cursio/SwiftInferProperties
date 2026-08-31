import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

/// **Instance-method `monotonicity` must quantify over the RECEIVER, and the curated tables
/// must be findable at the spelling discovery actually produces.**
///
/// Two halves of one fix, guarded together because either alone is inert — which is not a
/// guess: the key-space half was shipped alone earlier and **measured at zero rows moved**
/// (`docs/measurements/instance-method-shape-census.md` §3), because the carrier reaching the
/// lookup was still `Int`.
///
/// **What it cost to be missing.** `strategistBundle` anchored monotonicity at
/// `entry.carrierTypeName` — the *parameter* — so `OrderedSet.index(before:)` derived a
/// `Generator<Int>` and emitted `OrderedSet.index(before: someInt)`, a static call on an
/// instance method. **31 of 64 rows on `swift-collections` @ `899809d3` failed to build that
/// way**, and they are the template's only genuinely order-related population. After the fix:
/// **12 moved, 10 of them to `measured-bothPass`** — the first monotonicity verdicts of any
/// kind on that subject.
@Suite("Monotonicity — the generator quantifies over the receiver")
struct MonotonicityReceiverCarrierTests {

    private typealias VerifyCLI = SwiftInferCommand.Verify

    private static func entry(
        template: String = "monotonicity",
        owner: String? = "OrderedSet",
        parameter: String? = "Int",
        isInstanceMethod: Bool = true
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0x2106920EA35F0592",
            templateName: template,
            typeName: owner,
            score: 30,
            tier: "Possible",
            primaryFunctionName: "index(before:)",
            location: "/Module.swift:1",
            firstSeenAt: "2026-05-11T00:00:00Z",
            lastSeenAt: "2026-05-11T00:00:00Z",
            carrierTypeName: parameter,
            isInstanceMethod: isInstanceMethod
        )
    }

    /// **The regression.** Without this the carrier is `Int` and the stub emits a static call.
    @Test("an instance-method monotonicity entry anchors at its declaring type")
    func instanceMethodAnchorsAtReceiver() {
        #expect(
            VerifyCLI.monotonicityReceiverCarrier(entry: Self.entry()) == "OrderedSet",
            "the receiver is what must be generated; the parameter is an index into it"
        )
    }

    /// A free/static function's value IS the parameter, so the rule must not fire — the same
    /// direction `roundTripDomainCarrier` guards with `!entry.isInstanceMethod`.
    @Test("a non-instance-method entry is left alone")
    func staticIsLeftAlone() {
        #expect(VerifyCLI.monotonicityReceiverCarrier(entry: Self.entry(isInstanceMethod: false)) == nil)
    }

    /// Scoped to this template. `round-trip` has its own rule and must not be captured.
    @Test("another template is left alone")
    func otherTemplateIsLeftAlone() {
        #expect(VerifyCLI.monotonicityReceiverCarrier(entry: Self.entry(template: "round-trip")) == nil)
    }

    /// **The deliberate narrowing.** The rule is gated on a curated recipe existing, so a
    /// receiver the table cannot serve keeps its previous behaviour rather than trading one
    /// failure mode for an unmeasured other. `BitArray` is one of the 17 such carriers.
    @Test("a receiver with no curated recipe is left alone")
    func uncuratedReceiverIsLeftAlone() {
        #expect(VerifyCLI.monotonicityReceiverCarrier(entry: Self.entry(owner: "BitArray")) == nil)
    }

    /// **The key-space half.** The curated tables are written fully specialised and discovery
    /// produces bare names; both must resolve. Measured: of 34 distinct carriers in production
    /// output on that subject, **zero contain `<`**.
    @Test("curated recipes resolve on the bare name and the specialised one", arguments: [
        ("OrderedSet", "OrderedSet<Int>"),
        ("OrderedDictionary.Elements", "OrderedDictionary<Int, Int>.Elements"),
        ("OrderedDictionary.Values", "OrderedDictionary<Int, Int>.Values"),
        ("Deque", "Deque<Int>")
    ])
    func curatedRecipesResolveOnEitherSpelling(bare: String, specialised: String) {
        let viaBare = StrategistDispatchEmitter.curatedOCRecipe(carrier: bare)
        let viaSpecialised = StrategistDispatchEmitter.curatedOCRecipe(carrier: specialised)
        #expect(viaBare != nil, "the bare spelling is what discovery produces and must resolve")
        #expect(viaSpecialised != nil, "the specialised spelling is what the emitter tests supply")
        #expect(
            viaBare?.carrierTypeName == viaSpecialised?.carrierTypeName,
            "both spellings reach one recipe; its carrier stays SPECIALISED or the stub breaks"
        )
    }

    /// The composer's carrier test must accept both spellings for the same reason.
    @Test("the instance-carrier test accepts both spellings")
    func instanceCarrierTestAcceptsBothSpellings() {
        #expect(StrategistDispatchEmitter.isMonotonicityInstanceCarrier("OrderedSet"))
        #expect(StrategistDispatchEmitter.isMonotonicityInstanceCarrier("OrderedSet<Int>"))
        #expect(!StrategistDispatchEmitter.isMonotonicityInstanceCarrier("Deque"))
    }
}
