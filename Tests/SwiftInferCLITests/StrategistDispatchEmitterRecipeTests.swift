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
                StoredMember(name: "currency", typeName: "String"),
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

    // MARK: - Top-level composite carriers (WS-6 follow-up, kit 3.3.0)

    @Test("composite carrier [Money] with a universe resolver derives an array generator")
    func compositeArrayCarrierDerivesViaResolver() throws {
        // `[Money]` has no TypeShape of its own (the bare-name lookup misses the
        // `[...]` syntax), but Money is in the resolver universe — the composite
        // fallback resolves it to `<Money generator>.array(of:)`.
        let resolver = GeneratorResolver(types: [moneyKitShape()])
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "[Money]", typeShape: nil, resolve: resolver.customTypeGenerator
        )
        #expect(recipe.expression.contains("Money("))
        #expect(recipe.expression.contains(".array(of:"))
        #expect(recipe.carrierTypeName == "[Money]")
    }

    @Test("optional composite carrier Money? derives via the universe resolver")
    func compositeOptionalCarrierDerivesViaResolver() throws {
        let resolver = GeneratorResolver(types: [moneyKitShape()])
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "Money?", typeShape: nil, resolve: resolver.customTypeGenerator
        )
        #expect(recipe.expression.contains("Money("))
        #expect(recipe.expression.contains(".optional"))
    }

    @Test("composite carrier over an out-of-universe leaf still throws (no resolver)")
    func compositeCarrierUnresolvedLeafThrows() throws {
        // Default resolve `{ _ in nil }` — Money isn't reachable, so `[Money]`
        // bottoms out and the carrier stays unsupported (gen() guidance).
        #expect(throws: VerifyError.self) {
            _ = try StrategistDispatchEmitter.resolveRecipe(carrier: "[Money]", typeShape: nil)
        }
    }
}
