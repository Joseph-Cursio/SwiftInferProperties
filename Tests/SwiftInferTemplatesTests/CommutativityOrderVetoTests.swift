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

    /// **`OrderedDictionary` was removed from the denylist 2026-08-01**, so a
    /// user-written order-preserving `union` on it is no longer vetoed.
    ///
    /// Pinned as a deliberate hole rather than left to be rediscovered as a bug. It is
    /// the one carrier the structural rule can never cover even with perfect
    /// conformance data — `Sequence` and nothing that marks position as
    /// value-determined — so this arm going red means someone restored the entry, which
    /// is a decision, not a regression.
    @Test("OrderedDictionary is a KNOWN hole after the denylist entry was removed")
    func orderedDictionaryIsAKnownHole() {
        let conformances = ["OrderedDictionary": Set(["Sequence", "Equatable", "Hashable"])]
        #expect(!OrderedCarrierDiscriminator.isOrderSensitive(
            forConformances: conformances["OrderedDictionary"] ?? []
        ), "structural cannot see this carrier — that is why it needed a list entry")
        #expect(!OrderSensitiveCarrierNames.contains("OrderedDictionary"))

        let summary = makeCommutativitySummary(
            name: "union",
            paramTypes: ("OrderedDictionary", "OrderedDictionary"),
            returnType: "OrderedDictionary",
            containingType: "OrderedDictionary"
        )
        let signals = CommutativityTemplate.accumulatedSignals(
            for: summary, vocabulary: .empty, inheritedTypesByName: conformances
        )
        #expect(!signals.contains { $0.kind == .orderSensitiveCarrier })
    }

    /// **The remaining entries are load-bearing, and this arm exists to stop them being
    /// deleted as "redundant".**
    ///
    /// The structural rule needs a conformance record, and `ProtocolCoverageMap`'s
    /// curated stdlib bake-in contains no collection refinements at all. So in any
    /// corpus that does not itself contain the standard library — every application
    /// corpus — `Array` has no recorded conformances and only the denylist can see it.
    ///
    /// The survey reporting the two rules agreeing everywhere was run over *library*
    /// corpora, where the conformances are declared in the tree being scanned. That
    /// agreement measured the easy case.
    @Test("Array is vetoed by the denylist when no conformances are visible")
    func arrayIsVetoedWithoutConformanceRecords() {
        let summary = makeCommutativitySummary(
            name: "union",
            paramTypes: ("Array", "Array"),
            returnType: "Array",
            containingType: "Array"
        )
        // Empty index: exactly what an app corpus gives the structural rule.
        #expect(!OrderedCarrierDiscriminator.isOrderSensitive(forConformances: []))
        let signals = CommutativityTemplate.accumulatedSignals(
            for: summary, vocabulary: .empty, inheritedTypesByName: [:]
        )
        let veto = signals.first { $0.kind == .orderSensitiveCarrier }
        #expect(veto?.isVeto == true)
        #expect(veto?.detail.contains("curated order-sensitive carrier list") == true)
    }
}
