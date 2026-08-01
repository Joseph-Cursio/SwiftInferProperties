import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// B29's order-sensitive carrier veto, after migrating it from the six-name
/// `OrderSensitiveCarrierNames` denylist to `OrderedCarrierDiscriminator`.
///
/// Split from `CommutativityTemplateTests` on the `CommutativityTemplateShapeTests`
/// precedent — the file was at its SwiftLint length cap and these are a distinct
/// concern. Shares the `makeCommutativitySummary` builder in
/// `CommutativityTestSupport.swift`.
///
/// **What the migration buys**, and the reason each arm below exists: the veto now
/// fires on *any* carrier whose conformances make position value-determined, rather
/// than on six hardcoded names. Measured across swift-collections,
/// `stdlib/public/core`, swift-foundation, swift-syntax and swift-nio, the two rules
/// agree on every carrier declaring one of these verbs — zero disagreements and zero
/// change in suggestion counts. The gain is entirely on carriers nobody has written
/// yet, which is exactly what a curated denylist cannot cover.
@Suite("Commutativity — order-sensitive veto via the structural discriminator")
struct CommutativityOrderVetoTests {

    // MARK: - B29 via OrderedCarrierDiscriminator (structural, not the six-name list)

    /// **The capability the denylist could not have.** `Timeline` is a user-defined
    /// carrier on nobody's curated list; its conformances say position is
    /// value-determined, so an order-preserving `union` is not commutative and the
    /// veto now fires.
    @Test("A user-defined ordered carrier is vetoed structurally")
    func userDefinedOrderedCarrierIsVetoed() {
        let summary = makeCommutativitySummary(
            name: "union",
            paramTypes: ("Timeline", "Timeline"),
            returnType: "Timeline",
            containingType: "Timeline"
        )
        let conformances = [
            "Timeline": Set(["RandomAccessCollection", "ExpressibleByArrayLiteral", "Equatable"])
        ]
        #expect(CommutativityTemplate.suggest(
            for: summary, inheritedTypesByName: conformances
        ) == nil)
        let signals = CommutativityTemplate.accumulatedSignals(
            for: summary, vocabulary: .empty, inheritedTypesByName: conformances
        )
        let veto = signals.first { $0.kind == .orderSensitiveCarrier }
        #expect(veto?.isVeto == true)
        #expect(veto?.detail.contains("conformances make position value-determined") == true)
    }

    /// **Why the veto reads `isOrderSensitive` and not the full verdict.** `Ledger` is
    /// ordered but not `ExpressibleByArrayLiteral`, so the full verdict abstains — and
    /// an order-preserving `union` on it is still non-commutative. Reading the whole
    /// verdict here would have silently dropped `String`, `Substring`, `Data` and
    /// `Slice` too.
    @Test("An ordered carrier that is not element-determined is still vetoed")
    func orderedButNotElementDeterminedIsVetoed() {
        let summary = makeCommutativitySummary(
            name: "union",
            paramTypes: ("Ledger", "Ledger"),
            returnType: "Ledger",
            containingType: "Ledger"
        )
        let conformances = ["Ledger": Set(["RandomAccessCollection", "Equatable"])]
        #expect(CommutativityTemplate.suggest(
            for: summary, inheritedTypesByName: conformances
        ) == nil)
    }

    /// The other direction: a carrier whose conformances say order is NOT part of the
    /// value must keep its commutativity suggestion. `union` on a set-like carrier
    /// genuinely does commute.
    @Test("An unordered carrier is NOT vetoed by the order rule")
    func unorderedCarrierIsNotVetoed() {
        let summary = makeCommutativitySummary(
            name: "union",
            paramTypes: ("Tags", "Tags"),
            returnType: "Tags",
            containingType: "Tags"
        )
        let signals = CommutativityTemplate.accumulatedSignals(
            for: summary,
            vocabulary: .empty,
            inheritedTypesByName: ["Tags": Set(["Sequence", "Collection", "ExpressibleByArrayLiteral"])]
        )
        #expect(!signals.contains { $0.kind == .orderSensitiveCarrier })
    }

    /// The residue that keeps the denylist alive. `OrderedDictionary` conforms to
    /// `Sequence` and to nothing that marks position as value-determined, so the
    /// structural rule abstains — and the curated list still catches it. Measured on
    /// five corpora the two rules never disagree, but only because `OrderedDictionary`
    /// declares no set operations; this pins the case for the day one appears.
    @Test("OrderedDictionary is caught by the denylist where the structural rule abstains")
    func denylistCoversTheStructuralResidue() {
        let summary = makeCommutativitySummary(
            name: "union",
            paramTypes: ("OrderedDictionary", "OrderedDictionary"),
            returnType: "OrderedDictionary",
            containingType: "OrderedDictionary"
        )
        let conformances = ["OrderedDictionary": Set(["Sequence", "Equatable", "Hashable"])]
        #expect(!OrderedCarrierDiscriminator.isOrderSensitive(
            forConformances: conformances["OrderedDictionary"] ?? []
        ), "the structural rule abstains here — that is the point of the arm")
        let signals = CommutativityTemplate.accumulatedSignals(
            for: summary, vocabulary: .empty, inheritedTypesByName: conformances
        )
        let veto = signals.first { $0.kind == .orderSensitiveCarrier }
        #expect(veto?.isVeto == true)
        #expect(veto?.detail.contains("curated order-sensitive carrier list") == true)
    }
}
