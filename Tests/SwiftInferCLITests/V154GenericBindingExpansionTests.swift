import Testing

@testable import SwiftInferCLI

// MARK: - V1.52.D.4 — GenericBindingResolver expansion

@Suite("V1.54.B — GenericBindingResolver after V1.52.C key cleanup")
struct V154GenericBindingExpansionTests {

    // V1.54.B — V1.52.C's `<Type>.Index` entries were removed after
    // cycle-50 showed the indexer outputs bare type names (e.g.
    // `ChunkedByCollection`) so the `.Index` keys never matched.
    // Genuine chunked-Index coverage waits on v1.55+ TypeShape-driven
    // instance-method emission.

    @Test("V1.52.C dead bindings removed (regression guard)")
    func v1_52CKeysRemoved() {
        #expect(GenericBindingResolver.resolve("ChunkedByCollection.Index") == nil)
        #expect(GenericBindingResolver.resolve("ChunkedOnCollection.Index") == nil)
        #expect(GenericBindingResolver.resolve("ChunkedByLazyCollection.Index") == nil)
        #expect(GenericBindingResolver.resolve("OrderedSet.Index") == nil)
    }

    @Test("V1.47.D + V1.51.A bindings still resolve (regression guard)")
    func priorBindingsStillResolve() {
        // V1.47.D bindings (cycle-44 layer).
        #expect(GenericBindingResolver.resolve("Base.Index") == "Int")
        #expect(GenericBindingResolver.resolve("Base.Element") == "Int")
        #expect(GenericBindingResolver.resolve("Self.Index") == "Int")
        #expect(GenericBindingResolver.resolve("Self.Element") == "Int")
        #expect(GenericBindingResolver.resolve("Iterator.Element") == "Int")
        // V1.51.A bare→qualified.
        #expect(GenericBindingResolver.resolve("Complex") == "Complex<Double>")
    }

    @Test("unknown carrier name passes through unchanged")
    func unknownCarrierPassesThrough() {
        #expect(GenericBindingResolver.resolve("ChunkedByCollection.SubSequence") == nil)
        #expect(GenericBindingResolver.bound("ChunkedByCollection.SubSequence")
            == "ChunkedByCollection.SubSequence")
        // Bare type names that don't yet have a V1.58.A-style binding
        // also pass through.
        #expect(GenericBindingResolver.resolve("ChunkedByCollection") == nil)
        // V1.58.A added `"OrderedSet" → "OrderedSet<Int>"` so it no
        // longer passes through — covered by a dedicated test below.
    }

    @Test("V1.58.A: OrderedSet bare-name binds to OrderedSet<Int>")
    func orderedSetBindsToInt() {
        #expect(GenericBindingResolver.resolve("OrderedSet") == "OrderedSet<Int>")
        #expect(GenericBindingResolver.bound("OrderedSet") == "OrderedSet<Int>")
    }
}
