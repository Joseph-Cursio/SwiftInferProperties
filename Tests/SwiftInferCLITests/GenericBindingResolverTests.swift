import Foundation
import Testing

@testable import SwiftInferCLI

// V1.47.D — GenericBindingResolver curated-table tests.

@Suite("GenericBindingResolver — V1.47.D curated bindings")
struct GenericBindingResolverTests {

    @Test("Base.Index resolves to Int")
    func baseIndexResolvesToInt() {
        #expect(GenericBindingResolver.resolve("Base.Index") == "Int")
    }

    @Test("Base.Element resolves to Int")
    func baseElementResolvesToInt() {
        #expect(GenericBindingResolver.resolve("Base.Element") == "Int")
    }

    @Test("Self.Index + Self.Element resolve to Int")
    func selfFamilyResolvesToInt() {
        #expect(GenericBindingResolver.resolve("Self.Index") == "Int")
        #expect(GenericBindingResolver.resolve("Self.Element") == "Int")
    }

    @Test("Iterator.Element resolves to Int")
    func iteratorElementResolvesToInt() {
        #expect(GenericBindingResolver.resolve("Iterator.Element") == "Int")
    }

    @Test("unknown carrier returns nil")
    func unknownCarrierReturnsNil() {
        #expect(GenericBindingResolver.resolve("UnknownType") == nil)
        #expect(GenericBindingResolver.resolve("OrderedSet<Element>") == nil)
        #expect(GenericBindingResolver.resolve("") == nil)
    }

    @Test("bound() returns the binding when present, else the original")
    func boundReturnsBindingOrOriginal() {
        #expect(GenericBindingResolver.bound("Base.Index") == "Int")
        #expect(GenericBindingResolver.bound("OrderedSet<Element>") == "OrderedSet<Element>")
        #expect(GenericBindingResolver.bound("Int") == "Int")
    }

    @Test("Cycle 149 (Lever C-1): bare OrderedDictionary binds to OrderedDictionary<Int, Int>")
    func bareOrderedDictionaryBinds() {
        // The views (`.Elements` / `.Values` / `.Elements.SubSequence`)
        // were bound first; the dictionary itself was missing, so its
        // merge/sort picks couldn't resolve a recipe.
        #expect(GenericBindingResolver.resolve("OrderedDictionary") == "OrderedDictionary<Int, Int>")
        #expect(GenericBindingResolver.resolve("OrderedDictionary.Elements")
            == "OrderedDictionary<Int, Int>.Elements")
    }

    // MARK: - Bare `Self` — the binding that cannot be curated

    /// The carrier reach census over this repo's own 104-entry index measured a
    /// bare `Self` carrier as **6 of the 7 remaining `unsupported-carrier`
    /// declines**. It is absent from `curatedBindings` by necessity, not
    /// oversight: its value is the entry's owning type, so it has no fixed
    /// right-hand side.
    @Test("bare Self is deliberately NOT a curated binding")
    func bareSelfIsNotCurated() {
        #expect(GenericBindingResolver.resolve("Self") == nil)
        #expect(GenericBindingResolver.bound("Self") == "Self")
    }

    @Test("Self rebinds to the owning type")
    func selfRebindsToOwner() {
        #expect(GenericBindingResolver.bound("Self", selfType: "Decisions") == "Decisions")
        #expect(GenericBindingResolver.bound("Self", selfType: "SemanticIndexEntry") == "SemanticIndexEntry")
    }

    /// Without an owner there is nothing to rebind to, and `"(none)"` is the
    /// pipeline's spelling for "no owner recorded" — rebinding to it would turn
    /// a truthful `unsupported-carrier: Self` into a baffling one naming a type
    /// that does not exist.
    @Test("Self without a usable owner is left alone")
    func selfWithoutOwnerIsUnchanged() {
        #expect(GenericBindingResolver.bound("Self", selfType: nil) == "Self")
        #expect(GenericBindingResolver.bound("Self", selfType: "(none)") == "Self")
    }

    /// The rebind is scoped to the bare spelling. `Self.Index` / `Self.Element`
    /// are *associated types* of the conforming type, not the type itself, and
    /// their curated `Int` binding must survive — rebinding them to the owner
    /// would hand the strategist `Decisions.Index`, which derives nothing.
    @Test("Self.Index and Self.Element keep their curated bindings")
    func qualifiedSelfKeepsCuratedBinding() {
        #expect(GenericBindingResolver.bound("Self.Index", selfType: "Decisions") == "Int")
        #expect(GenericBindingResolver.bound("Self.Element", selfType: "Decisions") == "Int")
    }

    /// The owner is itself run through the curated table, so an owner recorded
    /// in bare form still lands on its bound spelling.
    @Test("a rebound owner is itself resolved through the curated table")
    func reboundOwnerIsAlsoResolved() {
        #expect(GenericBindingResolver.bound("Self", selfType: "OrderedSet") == "OrderedSet<Int>")
        #expect(GenericBindingResolver.bound("Self", selfType: "Complex") == "Complex<Double>")
    }

    @Test("the selfType overload leaves every non-Self carrier untouched")
    func nonSelfCarriersAreUnaffected() {
        #expect(GenericBindingResolver.bound("Int", selfType: "Decisions") == "Int")
        #expect(GenericBindingResolver.bound("String", selfType: "Decisions") == "String")
        #expect(GenericBindingResolver.bound("Base.Index", selfType: "Decisions") == "Int")
    }
}
