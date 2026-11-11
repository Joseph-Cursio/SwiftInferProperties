import Testing

@testable import SwiftInferCLI

// V1.51.E — unit tests for the three mechanical fixes (V1.51.A
// carrier normalization + V1.51.B dual-style pair expansion +
// V1.51.C v1.48-template routing flip).

@Suite("V1.51.A — bare→qualified carrier normalization")
struct V151CanonicalizationTests {

    @Test("Complex bare name canonicalizes to Complex<Double>")
    func complexCanonicalizes() {
        #expect(GenericBindingResolver.resolve("Complex") == "Complex<Double>")
        #expect(GenericBindingResolver.bound("Complex") == "Complex<Double>")
    }

    @Test("unknown bare names pass through unchanged")
    func unknownBareNamesPassThrough() {
        #expect(GenericBindingResolver.resolve("ComplexFlex") == nil)
        #expect(GenericBindingResolver.bound("ComplexFlex") == "ComplexFlex")
        // Existing carriers still pass through:
        #expect(GenericBindingResolver.bound("Double") == "Double")
        #expect(GenericBindingResolver.bound("Int") == "Int")
        #expect(GenericBindingResolver.bound("String") == "String")
    }

    @Test("V1.47.D bindings still resolve (regression guard)")
    func priorBindingsStillResolve() {
        #expect(GenericBindingResolver.resolve("Base.Index") == "Int")
        #expect(GenericBindingResolver.resolve("Self.Element") == "Int")
        #expect(GenericBindingResolver.resolve("Iterator.Element") == "Int")
    }
}
