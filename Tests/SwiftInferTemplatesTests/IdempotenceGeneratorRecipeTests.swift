import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("IdempotenceTemplate — generator recipes")
struct IdempotenceGeneratorRecipeTests {

    // A scalar String gets none: CollisionBias.collidingString is a path-flavored
    // *predicate* collision, not the idempotence one.
    @Test("A scalar String carrier ships no recipe")
    func stringCarrierGetsNoRecipe() {
        let summary = makeIdempotenceSummary(
            name: "normalize",
            paramType: "String",
            returnType: "String"
        )
        #expect(IdempotenceTemplate.suggest(for: summary)?.generatorRecipes.isEmpty == true)
    }

    @Test("A [String] carrier ships a collision-biased array recipe (T? -> T included)")
    func stringArrayCarrierGetsRecipe() {
        let summary = makeIdempotenceSummary(
            name: "mergedWith",
            paramType: "[String]?",
            returnType: "[String]"
        )
        let recipes = IdempotenceTemplate.suggest(for: summary)?.generatorRecipes ?? []
        #expect(recipes.contains { $0.typeName == "[String]" })
    }

    // Conservative, per PredicateTemplate's discipline: a small alphabet only helps
    // where structure collides, so an Int carrier gets no recipe.
    @Test("An Int carrier ships no recipe")
    func intCarrierGetsNoRecipe() {
        let summary = makeIdempotenceSummary(
            name: "normalize",
            paramType: "Int",
            returnType: "Int"
        )
        #expect(IdempotenceTemplate.suggest(for: summary)?.generatorRecipes.isEmpty == true)
    }
}
