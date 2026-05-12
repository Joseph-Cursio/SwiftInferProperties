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
}
