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

    @Test("raw-type carrier (String) resolves to the V1.150 edge-biased generator")
    func stringRawTypeRecipe() throws {
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "String", typeShape: nil
        )
        // Edge-biased: alphanumeric baseline mixed with curated structural edges
        // (whitespace / newline / `-` markers) so string-structural counterexamples
        // are reachable. The plain generator remains the majority arm.
        #expect(recipe.expression.contains("Gen<Character>.letterOrNumber.string(of: 0...8)"))
        #expect(recipe.expression.contains("Gen.frequency("))
        #expect(recipe.expression.contains("\"- \""))
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

    @Test("CaseIterable enum resolves to Gen.element(of: T.allCases).map { $0! }")
    func caseIterableRecipe() throws {
        let shape = IndexedTypeShape(
            name: "MyEnum", kind: .enum,
            inheritedTypes: ["CaseIterable"], hasUserGen: false
        )
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "MyEnum", typeShape: shape
        )
        // `element(of:)` yields an optional element → force-unwrap (allCases
        // is non-empty). The plain `Gen<T>.element(of:)` form fails to compile
        // (Value == C.Element?); latent until the first enum-carrier survey.
        #expect(recipe.expression == "Gen.element(of: MyEnum.allCases).map { $0! }")
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

    @Test("Cycle 149 (Lever C-1): bare OrderedDictionary<Int, Int> resolves to a curated recipe")
    func bareOrderedDictionaryRecipe() throws {
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "OrderedDictionary<Int, Int>", typeShape: nil
        )
        #expect(recipe.carrierTypeName == "OrderedDictionary<Int, Int>")
        // `viewSuffix: ""` returns the whole dictionary, no view projection.
        #expect(recipe.expression.contains("return dict }"))
        #expect(recipe.expression.contains(".elements") == false)
        #expect(recipe.imports.contains("OrderedCollections"))
    }

    @Test("non-raw, non-shape carrier throws .unsupportedCarrier")
    func unknownCarrierThrows() throws {
        #expect(throws: VerifyError.self) {
            _ = try StrategistDispatchEmitter.resolveRecipe(
                carrier: "UnknownType", typeShape: nil
            )
        }
    }

    // MARK: - WS-6 Slice 2 — recursive nested-type resolution at verify time

    /// `Wallet { balance: Money }` where `Money { amount: Int; currency: String }`
    /// is a sibling type in the universe. `balance`'s custom type can't resolve
    /// from Wallet's shape alone, so the bare-shape path leaves Wallet at `.todo`.
    private func walletShape() -> IndexedTypeShape {
        IndexedTypeShape(
            name: "Wallet", kind: .struct, inheritedTypes: [], hasUserGen: false,
            storedMembers: [IndexedTypeShape.StoredMember(name: "balance", typeName: "Money")],
            hasUserInit: false
        )
    }

    private func moneyKitShape() -> TypeShape {
        TypeShape(
            name: "Money", kind: .struct, inheritedTypes: [], hasUserGen: false,
            storedMembers: [
                StoredMember(name: "amount", typeName: "Int"),
                StoredMember(name: "currency", typeName: "String")
            ],
            hasUserInit: false
        )
    }

    @Test("WS-6 Slice 2: a whole-universe resolver recursively inlines a nested custom-type member")
    func recursiveResolverInlinesNestedMember() throws {
        let wallet = walletShape()
        let resolver = GeneratorResolver(types: [moneyKitShape(), wallet.toKitShape()])
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "Wallet", typeShape: wallet, resolve: resolver.customTypeGenerator
        )
        // Single-member memberwise: Wallet(balance: $0) over Money's inlined generator.
        #expect(recipe.expression.contains("Wallet(balance: $0)"))
        #expect(recipe.expression.contains("Money("))
    }

    @Test("WS-6 Slice 2: without the resolver the same nested carrier stays .todo (throws)")
    func withoutResolverNestedMemberThrows() throws {
        // Default resolve `{ _ in nil }` — the pre-WS-6 single-shape behavior.
        #expect(throws: VerifyError.self) {
            _ = try StrategistDispatchEmitter.resolveRecipe(
                carrier: "Wallet", typeShape: walletShape()
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

    // V1.60.A — mutating-instance-method emission for OC carriers.

    @Test("V1.60.A: idempotence on OrderedSet<Int> emits mutating-instance shape")
    func idempotenceOrderedSetMutatingShape() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "idempotence",
                carrier: "OrderedSet<Int>",
                functionCalls: ["OrderedSet.sort"]
            )
        )
        // The new mutating shape produces `var copy = value;
        // copy.sort()` instead of the static `OrderedSet.sort(value)`.
        #expect(source.contains("var onceCopy = value"))
        #expect(source.contains("onceCopy.sort()"))
        #expect(source.contains("var twiceCopy = value"))
        #expect(source.contains("twiceCopy.sort()"))
        // The static-shape call must NOT appear (regression guard).
        #expect(source.contains("OrderedSet.sort(value)") == false)
        #expect(source.contains("OrderedSet.sort(onceResult)") == false)
        // Standard VERIFY markers still emit.
        #expect(source.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(source.contains("VERIFY_DEFAULT_RESULT: FAIL"))
    }

    @Test("V1.60.A: idempotence on non-OC carrier still emits static shape (regression guard)")
    func idempotenceIntCarrierStaticShape() throws {
        // Int isn't in mutatingInstanceCarriers, so the existing
        // static-call emit shape stays.
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "idempotence",
                carrier: "Int",
                functionCalls: ["{ (x: Int) in x }"]
            )
        )
        #expect(source.contains("let onceResult"))
        #expect(source.contains("let twiceResult"))
        #expect(source.contains("var onceCopy") == false)
    }

    @Test("Cycle 149 (Lever C-1): dual-style merge on OrderedDictionary emits the uniquing closure on both halves")
    func dualStyleMergeEmitsUniquingClosure() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "dual-style-consistency",
                carrier: "OrderedDictionary<Int, Int>",
                functionCalls: ["OrderedDictionary.merging", "merge"]
            )
        )
        let closure = ", uniquingKeysWith: { (_, new) in new }"
        // Both halves must carry the SAME conflict closure so the
        // dual-style equivalence holds.
        #expect(source.contains("original.merging(other\(closure))"))
        #expect(source.contains("mutCopy.merge(other\(closure))"))
    }

    @Test("Cycle 149 (Lever C-1): dual-style SetAlgebra union takes no trailing closure (regression guard)")
    func dualStyleUnionNoTrailingClosure() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "dual-style-consistency",
                carrier: "OrderedSet<Int>",
                functionCalls: ["OrderedSet.union", "formUnion"]
            )
        )
        #expect(source.contains("original.union(other)"))
        #expect(source.contains("mutCopy.formUnion(other)"))
        #expect(source.contains("uniquingKeysWith") == false)
    }

    @Test("Cycle 149 (Lever C-1): dualStyleTrailingArgument keyed on mutating method name")
    func dualStyleTrailingArgumentLookup() {
        #expect(StrategistDispatchEmitter.dualStyleTrailingArgument(forMutating: "merge")
            == ", uniquingKeysWith: { (_, new) in new }")
        #expect(StrategistDispatchEmitter.dualStyleTrailingArgument(forMutating: "formUnion").isEmpty)
        #expect(StrategistDispatchEmitter.dualStyleTrailingArgument(forMutating: "sort").isEmpty)
    }
}
