import Foundation
import Testing

@testable import SwiftInferCore

/// **The generators the templates ship must COMPILE against the vendored `swift-property-based`.**
///
/// This is the B15a regression. Walk 6 handed three cold readers generators that looked runnable and
/// were not: `Gen.frequency` is `@available(swift 6.2)`, `Gen.array(of:count:)` is a *static* form the
/// kit does not have (it has an instance `.array(of:)`), and the carrier recipe emitted
/// `SomeType.gen()`, a method no type has. Every reader had to hand-re-implement the generator to run
/// it — the exact toil shipping a generator was meant to remove.
///
/// These tests cannot invoke `swiftc` on the emitted string, so they guard the property structurally:
/// the recipe text must not contain any construct known not to compile, and must use the forms that
/// do. The end-to-end proof that the emitted text compiles lives in the manual harness noted in B15a;
/// this keeps the three broken constructs from creeping back in.
@Suite("Generator recipes compile against the vendored kit")
struct GeneratorRecipeCompileSafetyTests {

    /// The constructs walk 6 caught, none of which compile against the pinned kit.
    private let bannedConstructs = [
        "Gen.frequency",        // @available(swift 6.2) — dead in an older language mode
        "Gen.array(of:",        // no such static; the kit has only an instance `.array(of:)`
        ".gen()"                // `SomeType.gen()` — no such method on an arbitrary carrier
    ]

    private func assertCompileSafe(_ recipe: GeneratorRecipe, _ label: String) {
        for banned in bannedConstructs {
            #expect(
                recipe.expression.contains(banned) == false,
                "\(label) still emits `\(banned)`, which does not compile against the vendored kit"
            )
        }
    }

    @Test("the colliding-string recipe uses only compile-safe API")
    func collidingStringIsCompileSafe() {
        let recipe = CollisionBias.collidingString(subject: "path")
        assertCompileSafe(recipe, "collidingString")
        // The forms that DO compile, so a future edit cannot silently drop them.
        #expect(recipe.expression.contains("Gen<String?>.element(of:"))
        #expect(recipe.expression.contains(".array(of: 0...6)"), "must use the INSTANCE array(of:)")
    }

    @Test("the carrier-state recipe no longer emits a nonexistent `.gen()`")
    func carrierStateIsCompileSafe() {
        let recipe = CollisionBias.carrierState(typeName: "ImmediateChildPredicate")
        assertCompileSafe(recipe, "carrierState")
        // It ships the runnable half — a colliding string — and names the manual carrier-init step.
        #expect(recipe.expression.contains("Gen<String?>.element(of:"))
        #expect(recipe.expression.contains("ImmediateChildPredicate("), "must name the init to feed")
    }

    @Test("the out-of-range index recipe is compile-safe")
    func outOfRangeIndexIsCompileSafe() {
        let recipe = CollisionBias.outOfRangeIndex(subject: "index")
        assertCompileSafe(recipe, "outOfRangeIndex")
        #expect(recipe.expression.contains("Gen<Int>.int(in: -50...500)"))
    }

    @Test("the tied-keys recipe is compile-safe")
    func tiedKeysIsCompileSafe() {
        let recipe = CollisionBias.tiedKeys(subject: "key", typeName: "String")
        assertCompileSafe(recipe, "tiedKeys")
        #expect(recipe.expression.contains("Gen<String?>.element(of:"))
    }
}
