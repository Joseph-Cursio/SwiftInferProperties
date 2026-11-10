import Foundation
import PropertyLawCore
import Testing

@testable import SwiftInferCLI
@testable import SwiftInferCore

// V1.49.E — unit tests for the V1.49.B .memberwiseArbitrary emit.

@Suite("V1.49.B — memberwiseArbitrary strategy emit")
struct V149MemberwiseTests {

    @Test("1-member struct emits map() with constructor call")
    func singleMemberEmitShape() throws {
        let shape = IndexedTypeShape(
            name: "Wrapper",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: [
                IndexedTypeShape.StoredMember(name: "value", typeName: "Int")
            ],
            hasUserInit: false
        )
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "Wrapper", typeShape: shape
        )
        #expect(recipe.expression.contains("Gen<Int>.int()"))
        #expect(recipe.expression.contains(".map"))
        #expect(recipe.expression.contains("Wrapper(value: $0)"))
        #expect(!recipe.expression.contains("zip("))
    }

    @Test("2-member struct emits zip(g1, g2).map composition")
    func twoMemberEmitShape() throws {
        let shape = IndexedTypeShape(
            name: "Pair",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: [
                IndexedTypeShape.StoredMember(name: "x", typeName: "Int"),
                IndexedTypeShape.StoredMember(name: "y", typeName: "String"),
            ],
            hasUserInit: false
        )
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "Pair", typeShape: shape
        )
        #expect(recipe.expression.contains("zip(Gen<Int>.int(), Gen<Character>.letterOrNumber.string(of: 0...8))"))
        #expect(recipe.expression.contains("(m0, m1)"))
        #expect(recipe.expression.contains("Pair(x: m0, y: m1)"))
    }

    @Test("3-member struct emits zip(g1, g2, g3).map composition")
    func threeMemberEmitShape() throws {
        let shape = IndexedTypeShape(
            name: "Triple",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: [
                IndexedTypeShape.StoredMember(name: "a", typeName: "Int"),
                IndexedTypeShape.StoredMember(name: "b", typeName: "Int"),
                IndexedTypeShape.StoredMember(name: "c", typeName: "Bool"),
            ],
            hasUserInit: false
        )
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "Triple", typeShape: shape
        )
        #expect(recipe.expression.contains("zip(Gen<Int>.int(), Gen<Int>.int(), Gen<Bool>.bool())"))
        #expect(recipe.expression.contains("(m0, m1, m2)"))
        #expect(recipe.expression.contains("Triple(a: m0, b: m1, c: m2)"))
    }

    @Test("non-stdlib member type falls through to .todo via strategist")
    func nonStdlibMemberFallsThroughToTodo() throws {
        // Stored property Widget is a bespoke type with no recognized
        // generator — strategist returns .todo, our emitter throws
        // .unsupportedCarrier. (URL et al. now auto-derive as of kit v3.11.0.)
        let shape = IndexedTypeShape(
            name: "Unsupported",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: [
                IndexedTypeShape.StoredMember(name: "widget", typeName: "Widget")
            ],
            hasUserInit: false
        )
        #expect(throws: VerifyError.self) {
            _ = try StrategistDispatchEmitter.resolveRecipe(
                carrier: "Unsupported", typeShape: shape
            )
        }
    }
}
