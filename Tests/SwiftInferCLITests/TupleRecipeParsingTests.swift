@testable import SwiftInferCLI
import Testing

/// The tuple-carrier parser — splitting a tuple type spelling into its top-level
/// components, respecting nested brackets and stripping labels, so the `zip`
/// recipe can generate `(A, B, …)` carriers the kit's `composedGenerator` skips.
@Suite("Tuple recipe — type-spelling parsing")
struct TupleRecipeParsingTests {

    private typealias Emitter = StrategistDispatchEmitter

    @Test("a plain two-element tuple splits into its components")
    func plainPair() {
        #expect(Emitter.tupleComponents(of: "(Int, Int)") == ["Int", "Int"])
    }

    @Test("mixed component types split")
    func mixedComponents() {
        #expect(Emitter.tupleComponents(of: "(Int, String, Bool)") == ["Int", "String", "Bool"])
    }

    @Test("a nested Dictionary component is not split on its inner colon or comma")
    func nestedDictionaryStaysIntact() {
        #expect(Emitter.tupleComponents(of: "([Int: String], Bool)") == ["[Int: String]", "Bool"])
    }

    @Test("a nested tuple component stays intact")
    func nestedTupleStaysIntact() {
        #expect(Emitter.tupleComponents(of: "((Int, Int), Bool)") == ["(Int, Int)", "Bool"])
    }

    @Test("a nested generic component stays intact")
    func nestedGenericStaysIntact() {
        #expect(Emitter.tupleComponents(of: "(Set<Int>, Array<String>)") == ["Set<Int>", "Array<String>"])
    }

    @Test("labelled components are unwrapped to their types")
    func labelledComponentsUnwrapped() {
        #expect(Emitter.tupleComponents(of: "(x: Int, y: Int)") == ["Int", "Int"])
    }

    @Test("a single parenthesized type is NOT a tuple")
    func singleParenthesizedIsNotTuple() {
        #expect(Emitter.tupleComponents(of: "(Int)") == nil)
    }

    @Test("Void () is not a tuple")
    func voidIsNotTuple() {
        #expect(Emitter.tupleComponents(of: "()") == nil)
    }

    @Test("a non-tuple type returns nil")
    func nonTupleReturnsNil() {
        #expect(Emitter.tupleComponents(of: "Int") == nil)
        #expect(Emitter.tupleComponents(of: "[Int]") == nil)
    }

    @Test("a scalar-component tuple resolves to a zip recipe")
    func scalarTupleRecipe() throws {
        let recipe = try #require(Emitter.tupleRecipe(carrier: "(Int, Int)") { _ in nil })
        #expect(recipe.carrierTypeName == "(Int, Int)")
        #expect(recipe.expression == "zip(Gen<Int>.int(), Gen<Int>.int())")
        #expect(!recipe.expression.contains("\n"))
    }

    @Test("a 10-element tuple exceeds the kit's zip arity and gates")
    func tooManyComponentsGate() {
        let ten = "(" + Array(repeating: "Int", count: 10).joined(separator: ", ") + ")"
        #expect((Emitter.tupleRecipe(carrier: ten) { _ in nil }) == nil)
    }
}
