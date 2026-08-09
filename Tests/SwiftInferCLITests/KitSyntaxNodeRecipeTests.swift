@testable import SwiftInferCLI
import Testing

/// The kit-backed fallback for syntax node carriers the curated table does not name.
///
/// **The arms that must NOT fire are the point.** A fallback keyed on a name suffix
/// is one wrong `hasSuffix` away from claiming a generator for types it cannot
/// generate, and the failure would be silent in the direction that matters: a
/// recipe that compiles but draws the wrong thing changes a verdict, where a
/// recipe that does not compile only loses the entry it was for.
@Suite("Kit syntax-node recipe — the fallback after the curated table")
struct KitSyntaxNodeRecipeTests {

    /// The five carriers the 2026-08-09 `SwiftInferCore` survey blocked on.
    @Test(
        "the surveyed blocked node kinds get a recipe",
        arguments: [
            "DeclModifierListSyntax",
            "CodeBlockItemSyntax",
            "StringLiteralExprSyntax",
            "InheritanceClauseSyntax",
            "DictionaryExprSyntax"
        ]
    )
    func blockedNodeKindsResolve(carrier: String) {
        let recipe = StrategistDispatchEmitter.kitSyntaxNodeRecipe(carrier: carrier)
        #expect(recipe != nil, "\(carrier) is a syntax node; the kit generates it generically")
        #expect(recipe?.expression == "Gen<\(carrier)>.syntaxNode()")
        #expect(recipe?.imports.contains("PropertyLawSyntax") == true)
    }

    /// `InheritanceClauseSyntax?` is a real surveyed carrier. The recipe is for the
    /// wrapped type — optionality is the composite path's business, not this one's.
    @Test("a trailing ? is unwrapped, and the recipe names the bare type")
    func optionalIsUnwrapped() {
        let recipe = StrategistDispatchEmitter.kitSyntaxNodeRecipe(carrier: "InheritanceClauseSyntax?")
        #expect(recipe?.carrierTypeName == "InheritanceClauseSyntax")
        #expect(recipe?.expression == "Gen<InheritanceClauseSyntax>.syntaxNode()")
    }

    /// **Curated wins.** A curated recipe navigates to the specific shape its law is
    /// about; the generic one draws from a pool. If this arm ever fails, laws that
    /// currently bite have been silently weakened.
    @Test(
        "a curated carrier is declined so the curated recipe keeps priority",
        arguments: ["FunctionDeclSyntax", "SourceFileSyntax", "TokenSyntax", "StructDeclSyntax"]
    )
    func curatedCarriersAreDeclined(carrier: String) {
        #expect(
            StrategistDispatchEmitter.kitSyntaxNodeRecipe(carrier: carrier) == nil,
            "\(carrier) is curated; the fallback must not shadow it"
        )
    }

    /// Collections reach the kit through `GeneratorPlan.array` / `.arraySlice` over
    /// the ELEMENT. Answering here would state a generator for the container that
    /// the kit would also derive, and the two need not agree.
    @Test(
        "collection and generic spellings are declined",
        arguments: [
            "[CodeBlockItemSyntax]",
            "ArraySlice<CodeBlockItemSyntax>",
            "Ranked<DeclSyntax>"
        ]
    )
    func collectionsAreDeclined(carrier: String) {
        #expect(StrategistDispatchEmitter.kitSyntaxNodeRecipe(carrier: carrier) == nil)
    }

    /// The suffix gate is swift-syntax's own generated-code convention, so it must
    /// not fire on ordinary types — including this repo's own visitors, which are
    /// traversals rather than values and are correct to leave unsupported.
    @Test(
        "non-node carriers are declined",
        arguments: ["FunctionScannerVisitor", "BodySignalVisitor", "String", "Effect", "Syntactic"]
    )
    func nonNodeCarriersAreDeclined(carrier: String) {
        #expect(StrategistDispatchEmitter.kitSyntaxNodeRecipe(carrier: carrier) == nil)
    }

    /// The population guard: if the curated table ever absorbs every kind the
    /// fallback answers for, this suite would pass while testing nothing.
    @Test("the curated table does not already cover the blocked kinds")
    func fallbackPopulationIsNonEmpty() {
        let curated = Set(StrategistDispatchEmitter.curatedSyntaxRecipeCarriers)
        #expect(!curated.isEmpty, "the curated table is the thing being deferred to")
        #expect(!curated.contains("DeclModifierListSyntax"))
    }
}
