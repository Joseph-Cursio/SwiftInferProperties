import Foundation
import PropertyLawCore
@testable import SwiftInferCLI
import Testing

/// A syntax node in **leaf** position — `[CodeBlockItemSyntax]` — must resolve, not just
/// the same node as a top-level carrier.
///
/// The composite branch hands each leaf to `resolve`, which knows only the indexed shape
/// universe. A swift-syntax node has no indexed shape, so the leaf answered nil and the
/// whole composition collapsed — for an element the emitter can generate one call earlier.
@Suite("Syntax-aware resolve — nodes in leaf position")
struct SyntaxAwareResolveTests {

    private var neverResolves: (String) -> DerivationStrategist.ComposedGenerator? {
        { _ in nil }
    }

    /// The three rows §9.3 left declining, by element type.
    @Test(
        "a syntax leaf the base resolver cannot answer now resolves",
        arguments: ["CodeBlockItemSyntax", "DeclModifierListSyntax", "DictionaryExprSyntax"]
    )
    func syntaxLeafResolves(name: String) {
        let resolved = StrategistDispatchEmitter.syntaxAwareResolve(neverResolves)(name)
        #expect(resolved != nil, "\(name) is generatable as a top-level carrier already")
        #expect(resolved?.expression.contains(name) == true)
    }

    /// A curated leaf keeps its curated navigation rather than falling to the pool.
    @Test("a curated leaf resolves through the curated recipe")
    func curatedLeafKeepsItsRecipe() {
        let resolved = StrategistDispatchEmitter.syntaxAwareResolve(neverResolves)("FunctionDeclSyntax")
        #expect(resolved != nil)
        #expect(
            resolved?.expression.contains("syntaxNode()") == false,
            "curated recipes parse a corpus; falling to the generic pool would lose the targeting"
        )
    }

    /// **The arm that must not fire.** The indexed universe wins; a declared type keeps
    /// its real shape even if its name ends in `Syntax`.
    @Test("the base resolver is never overridden")
    func baseResolverWins() {
        let base: (String) -> DerivationStrategist.ComposedGenerator? = { name in
            name == "MySyntax" ? DerivationStrategist.ComposedGenerator(expression: "REAL") : nil
        }
        #expect(StrategistDispatchEmitter.syntaxAwareResolve(base)("MySyntax")?.expression == "REAL")
    }

    /// A non-syntax leaf the base cannot answer stays unresolved — the wrapper must not
    /// invent generators for ordinary unknown types.
    @Test(
        "a non-syntax leaf stays nil",
        arguments: ["Effect", "SamplingSeed", "FunctionSummary", "Visitor"]
    )
    func nonSyntaxLeafStaysNil(name: String) {
        #expect(StrategistDispatchEmitter.syntaxAwareResolve(neverResolves)(name) == nil)
    }

    /// The leaf declares its own imports, so the collection case does not have to know.
    @Test("a kit-backed leaf carries PropertyLawSyntax in its imports")
    func leafCarriesItsImports() {
        let resolved = StrategistDispatchEmitter.syntaxAwareResolve(neverResolves)("CodeBlockItemSyntax")
        #expect(resolved?.requiredImports.contains("PropertyLawSyntax") == true)
    }
}
