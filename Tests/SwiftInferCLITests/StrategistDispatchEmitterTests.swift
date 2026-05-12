import Foundation
import PropertyLawCore
import Testing

@testable import SwiftInferCLI
@testable import SwiftInferCore

// V1.47.E — StrategistDispatchEmitter tests. Covers the 5-strategy
// × 4-template dispatch matrix the v1.47 plan calls for, plus
// recipe-resolution behavior for raw types, .userGen, .caseIterable,
// .rawRepresentable, .memberwiseArbitrary (rejection), and .todo
// (rejection).

@Suite("StrategistDispatchEmitter — V1.47.E recipe resolution")
struct StrategistDispatchEmitterRecipeTests {

    @Test("raw-type carrier (Int) without typeShape resolves to direct generator")
    func intRawTypeRecipe() throws {
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "Int", typeShape: nil
        )
        #expect(recipe.expression == "Gen<Int>.int()")
        #expect(recipe.carrierTypeName == "Int")
        #expect(recipe.imports.contains("PropertyBased"))
    }

    @Test("raw-type carrier (String) resolves to letterOrNumber generator")
    func stringRawTypeRecipe() throws {
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "String", typeShape: nil
        )
        #expect(recipe.expression == "Gen<Character>.letterOrNumber.string(of: 0...8)")
    }

    @Test("user-gen typeShape resolves to <Type>.gen()")
    func userGenRecipe() throws {
        let shape = IndexedTypeShape(
            name: "MyType", kind: .struct, inheritedTypes: [], hasUserGen: true
        )
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "MyType", typeShape: shape
        )
        #expect(recipe.expression == "MyType.gen()")
    }

    @Test("CaseIterable enum resolves to Gen<T>.element(of: T.allCases)")
    func caseIterableRecipe() throws {
        let shape = IndexedTypeShape(
            name: "MyEnum", kind: .enum,
            inheritedTypes: ["CaseIterable"], hasUserGen: false
        )
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "MyEnum", typeShape: shape
        )
        #expect(recipe.expression == "Gen<MyEnum>.element(of: MyEnum.allCases)")
    }

    @Test("rawRepresentable enum resolves to lifted compactMap")
    func rawRepresentableRecipe() throws {
        let shape = IndexedTypeShape(
            name: "MyEnum", kind: .enum,
            inheritedTypes: ["Int"], hasUserGen: false
        )
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "MyEnum", typeShape: shape
        )
        #expect(recipe.expression.contains("Gen<Int>.int()"))
        #expect(recipe.expression.contains(".compactMap"))
        #expect(recipe.expression.contains("MyEnum(rawValue:"))
    }

    @Test("memberwise-arbitrary 1-member emits map() with constructor call (V1.49.B)")
    func memberwiseSingleMember() throws {
        let shape = IndexedTypeShape(
            name: "MyStruct", kind: .struct,
            inheritedTypes: [], hasUserGen: false,
            storedMembers: [
                IndexedTypeShape.StoredMember(name: "x", typeName: "Int")
            ],
            hasUserInit: false
        )
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "MyStruct", typeShape: shape
        )
        // 1-member uses `.map`, not `zip`.
        #expect(recipe.expression.contains("Gen<Int>.int()"))
        #expect(recipe.expression.contains(".map"))
        #expect(recipe.expression.contains("MyStruct(x: $0)"))
        #expect(!recipe.expression.contains("zip("))
    }

    @Test("non-raw, non-shape carrier throws .unsupportedCarrier")
    func unknownCarrierThrows() throws {
        #expect(throws: VerifyError.self) {
            _ = try StrategistDispatchEmitter.resolveRecipe(
                carrier: "UnknownType", typeShape: nil
            )
        }
    }
}

@Suite("StrategistDispatchEmitter — V1.47.E template × emit dispatch")
struct StrategistDispatchEmitterEmitTests {

    private static let canonicalSeed = StrategistDispatchEmitter.SeedHex(
        stateA: 0x01, stateB: 0x02, stateC: 0x03, stateD: 0x04
    )

    private static func inputs(
        template: String,
        carrier: String = "Int",
        functionCalls: [String] = ["{ (x: Int) in x }"],
        trialBudget: StrategistDispatchEmitter.TrialBudget = .small
    ) -> StrategistDispatchEmitter.Inputs {
        StrategistDispatchEmitter.Inputs(
            carrier: carrier,
            typeShape: nil,
            template: template,
            functionCalls: functionCalls,
            extraImports: [],
            seedHex: canonicalSeed,
            trialBudget: trialBudget
        )
    }

    @Test("round-trip emits forward+inverse calls + VERIFY markers + zero-edge sentinel")
    func roundTripEmitShape() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "round-trip",
                functionCalls: [
                    "{ (x: Int) in x + 1 }",
                    "{ (x: Int) in x - 1 }"
                ]
            )
        )
        #expect(source.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(source.contains("VERIFY_DEFAULT_RESULT: FAIL"))
        #expect(source.contains("Gen<Int>.int()"))
        #expect(source.contains("{ (x: Int) in x + 1 }(value)"))
        #expect(source.contains("{ (x: Int) in x - 1 }(forwardResult)"))
        #expect(source.contains("VERIFY_EDGE_RESULT: PASS"))
        #expect(source.contains("VERIFY_EDGE_TRIALS: 0"))
    }

    @Test("idempotence emits f(f(x)) shape")
    func idempotenceEmitShape() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "idempotence",
                functionCalls: ["{ (x: Int) in x * x }"]
            )
        )
        #expect(source.contains("let onceResult = { (x: Int) in x * x }(value)"))
        #expect(source.contains("let twiceResult = { (x: Int) in x * x }(onceResult)"))
        #expect(source.contains("onceResult != twiceResult"))
    }

    @Test("commutativity emits 2-value f(a, b) / f(b, a) shape")
    func commutativityEmitShape() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "commutativity",
                functionCalls: ["{ (a: Int, b: Int) in a + b }"]
            )
        )
        #expect(source.contains("let lhs = defaultGenerator.run"))
        #expect(source.contains("let rhs = defaultGenerator.run"))
        #expect(source.contains("(lhs, rhs)"))
        #expect(source.contains("(rhs, lhs)"))
    }

    @Test("associativity emits 3-value nested-call shape")
    func associativityEmitShape() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "associativity",
                functionCalls: ["{ (a: Int, b: Int) in a + b }"]
            )
        )
        #expect(source.contains("let valueA = defaultGenerator.run"))
        #expect(source.contains("let valueB = defaultGenerator.run"))
        #expect(source.contains("let valueC = defaultGenerator.run"))
        #expect(source.contains("(valueA, valueB), valueC)"))
        #expect(source.contains("(valueA, "))
    }

    @Test("unsupported template throws .unsupportedTemplate")
    func unsupportedTemplateThrows() throws {
        // V1.48.A widened the supported template set to 7 entries
        // (added idempotence-lifted, dual-style-consistency,
        // monotonicity). Use a template name outside that set to
        // exercise the .unsupportedTemplate path.
        #expect(throws: VerifyError.self) {
            _ = try StrategistDispatchEmitter.emit(
                Self.inputs(template: "homomorphism")
            )
        }
    }

    @Test("seed hex renders into the stub")
    func seedHexRenders() throws {
        let source = try StrategistDispatchEmitter.emit(Self.inputs(template: "idempotence"))
        #expect(source.contains("0x1"))
        #expect(source.contains("0x2"))
        #expect(source.contains("0x3"))
        #expect(source.contains("0x4"))
    }

    @Test("trial budget renders into the stub (small = 100)")
    func smallBudgetRenders() throws {
        let source = try StrategistDispatchEmitter.emit(Self.inputs(template: "idempotence"))
        #expect(source.contains("let trials = 100"))
    }
}
