import SwiftInferCore
import Testing

/// The **collection half** of the stdlib conformance bake-in, added 2026-08-01.
///
/// V1.7.1 built the bake-in to close a *numeric* finding and never revisited it. By the
/// time `OrderedCarrierDiscriminator` started reading the conformance index there were
/// twelve consumers, and the table still held nothing but scalars — so any carrier from
/// the standard library's collection surface was invisible to all of them.
///
/// The symptom is corpus-shaped and therefore easy to miss: in a **library** corpus
/// `Array`'s conformances are declared in the tree being scanned, so everything works.
/// In an **application** corpus they are not, and the tool was falling back to a
/// six-name curated denylist.
@Suite("Stdlib bake-in — the collection family")
struct StdlibCollectionBakeInTests {

    // MARK: - What was added

    @Test(
        "The array family carries its unconditional collection refinements",
        arguments: ["Array", "ContiguousArray", "ArraySlice"]
    )
    func arrayFamilyHasCollectionRefinements(name: String) {
        let index = ProtocolCoverageMap.inheritedTypesIndex(from: [])
        let conformances = index[name] ?? []
        for expected in [
            "Sequence", "Collection", "BidirectionalCollection", "RandomAccessCollection",
            "MutableCollection", "RangeReplaceableCollection", "ExpressibleByArrayLiteral"
        ] {
            #expect(conformances.contains(expected), "\(name) is missing \(expected)")
        }
    }

    @Test("Set carries SetAlgebra, which is what marks order as NOT part of its value")
    func setCarriesSetAlgebra() {
        let index = ProtocolCoverageMap.inheritedTypesIndex(from: [])
        #expect(index["Set"]?.contains("SetAlgebra") == true)
    }

    /// `String` is `BidirectionalCollection` but deliberately **not**
    /// `RandomAccessCollection` (grapheme breaking makes index offsetting linear) and not
    /// `ExpressibleByArrayLiteral`.
    @Test("String gains its collection refinements without gaining RandomAccess")
    func stringCollectionShape() {
        let conformances = ProtocolCoverageMap.inheritedTypesIndex(from: [])["String"] ?? []
        #expect(conformances.contains("BidirectionalCollection"))
        #expect(conformances.contains("RangeReplaceableCollection"))
        #expect(!conformances.contains("RandomAccessCollection"))
        #expect(!conformances.contains("ExpressibleByArrayLiteral"))
        // The pre-existing scalar entries survive the merge.
        #expect(conformances.contains("Comparable"))
        #expect(conformances.contains("Codable"))
    }

    // MARK: - What was deliberately NOT added

    /// **The line this change had to stay behind.** `Array<T>: Equatable` holds only
    /// `where T: Equatable`, and the bake-in's own doc rules conditional conformance out
    /// of scope: *"the textual scan can't tell whether a generic argument satisfies a
    /// constraint without semantic resolution."*
    ///
    /// Adding it would contradict that recorded decision **and** silently drop the
    /// `Equatable` caveat from every `Array`-carried suggestion on the strength of a
    /// guess. Measured: the caveat count on swift-foundation is unchanged at 722 either
    /// side of this change, which is the observable form of this arm.
    @Test(
        "No conditional conformances leaked in with the collection refinements",
        arguments: ["Array", "ContiguousArray", "ArraySlice", "Set", "Dictionary"]
    )
    func noConditionalConformances(name: String) {
        let conformances = ProtocolCoverageMap.inheritedTypesIndex(from: [])[name] ?? []
        for conditional in ["Equatable", "Hashable", "Codable", "Comparable"] {
            #expect(
                !conformances.contains(conditional),
                "\(name): \(conditional) is CONDITIONAL on the element type and must not be baked in"
            )
        }
    }

    /// `Range` / `ClosedRange` are absent for the same reason — their `Collection`
    /// conformance is conditional on `Bound: Strideable`.
    @Test("Range is not baked in", arguments: ["Range", "ClosedRange"])
    func rangeIsAbsent(name: String) {
        #expect(ProtocolCoverageMap.inheritedTypesIndex(from: [])[name] == nil)
    }

    // MARK: - What it unblocks

    /// The motivating case. With no corpus type declarations at all — exactly what an
    /// application corpus gives the resolver — the discriminator can now answer for
    /// `Array`, where before it abstained and only the curated denylist could see it.
    @Test("Array is structurally order-sensitive from the bake-in alone")
    func arrayIsOrderSensitiveFromTheBakeIn() {
        let index = ProtocolCoverageMap.inheritedTypesIndex(from: [])
        #expect(OrderedCarrierDiscriminator.isOrderSensitive(forConformances: index["Array"] ?? []))
        #expect(OrderedCarrierDiscriminator.isOrderSensitive(forConformances: index["String"] ?? []))
        // And the other direction: SetAlgebra says order is not part of Set's value, so a
        // `union` on it genuinely does commute and must not be vetoed.
        #expect(!OrderedCarrierDiscriminator.isOrderSensitive(forConformances: index["Set"] ?? []))
    }

    /// The sequence-view model law must NOT start firing on stdlib collections as a side
    /// effect. It needs a hand-written `==` in the scanned corpus, which an application
    /// corpus does not have for `Array` — but the element-determined gate is the belt to
    /// that braces, and this pins it.
    @Test("String stays out of the sequence-view model law's reach")
    func stringStillAbstainsForTheModelLaw() {
        let index = ProtocolCoverageMap.inheritedTypesIndex(from: [])
        let verdict = OrderedCarrierDiscriminator.verdict(forConformances: index["String"] ?? [])
        #expect(verdict == .abstain(.notElementDetermined))
    }
}
