import Foundation
import PropertyLawCore

/// The **kit-backed** half of syntax-node generation, split from
/// `StrategistDispatchEmitter+SyntaxRecipes` on 2026-08-09 when adding leaf resolution took
/// that file to 401 lines against the 400 cap. The unit moved rather than the reasoning
/// being trimmed, following the rule `docs/design/signal-kind-rationales.md` states for
/// `Signal+Kind`.
///
/// It is a real seam, not an arithmetic split. That file is a hand-curated table: one
/// navigation per node kind, each with its own snippet corpus, where the corpus IS the
/// measurement. This one is the opposite policy — a generic delegation to the kit's
/// `Gen<T>.syntaxNode()`, which answers for kinds nobody enumerated. They are consulted in
/// that order everywhere, and the ordering is the point: curated targeting first, generic
/// coverage for the tail.
extension StrategistDispatchEmitter {

    /// Wrap a whole-module resolver so a **syntax node in leaf position** resolves too.
    ///
    /// ## The gap this closes
    ///
    /// `resolveRecipe` consults the syntax tables for the *top-level* carrier, so
    /// `CodeBlockItemSyntax` derives — but `[CodeBlockItemSyntax]` takes the composite
    /// branch instead, where `DerivationStrategist.composedGenerator` recurses through
    /// `Array`/`Set`/`Optional`/`Dictionary` and hands each **leaf** to `resolve`. That
    /// resolver only knows the indexed shape universe, and a swift-syntax node has no
    /// indexed shape, so the leaf answers nil and the whole composition collapses to
    /// `unsupported-carrier` — for an element type the emitter can generate perfectly well
    /// one call earlier.
    ///
    /// Measured (`roadtest-self-dogfood-2026-08-08.md` §9.3): the top-level fix moved 6 of 9
    /// rows and left exactly the 3 collection spellings — `[CodeBlockItemSyntax]` ×2 and
    /// `ArraySlice<CodeBlockItemSyntax>` — declining for this reason.
    ///
    /// ## Order, and why the base resolver wins
    ///
    /// The indexed universe is consulted **first** and is never overridden. A type the
    /// module actually declares must keep its real shape even if its name happens to end in
    /// `Syntax`; the fallback is for leaves the resolver genuinely cannot answer. Within the
    /// fallback the curated table precedes the generic pool, the same priority
    /// `resolveRecipe` applies at top level and for the same reason.
    ///
    /// Imports ride along on the `ComposedGenerator`, and the composite branch already
    /// unions `composed.requiredImports` into the stub's import block — so a leaf that needs
    /// `PropertyLawSyntax` says so itself rather than the collection case having to know.
    static func syntaxAwareResolve(
        _ base: @escaping (String) -> DerivationStrategist.ComposedGenerator?
    ) -> (String) -> DerivationStrategist.ComposedGenerator? {
        { name in
            if let resolved = base(name) { return resolved }
            guard let recipe = curatedSyntaxRecipe(carrier: name)
                ?? kitSyntaxNodeRecipe(carrier: name) else { return nil }
            return DerivationStrategist.ComposedGenerator(
                expression: recipe.expression,
                requiredImports: Set(recipe.imports)
            )
        }
    }

    /// Fallback for a syntax node the curated table does not name: delegate to
    /// the kit's `Gen<T>.syntaxNode()`, which is written **generically over
    /// `SyntaxProtocol`** rather than per type.
    ///
    /// ## Why a fallback rather than sixteen more curated entries
    ///
    /// The curated table is 16 carriers and the survey blocks on five it does
    /// not name (`DeclModifierListSyntax`, `CodeBlockItemSyntax`,
    /// `StringLiteralExprSyntax`, `InheritanceClauseSyntax`,
    /// `DictionaryExprSyntax`). Hand-writing a navigation per kind is how that
    /// table got to 16 and it does not converge — swift-syntax has hundreds of
    /// node kinds. The kit's generator parses a snippet pool and pulls nodes of
    /// the requested kind out of it, so it answers for a kind nobody enumerated.
    ///
    /// **Curated wins on purpose.** Consulted only AFTER `curatedSyntaxRecipe`,
    /// because a curated recipe navigates to a *specific shape* the law is about
    /// (`funcCorpus` → the `FunctionDeclSyntax` of a function that throws),
    /// while the generic one draws whatever the pool happens to contain. Losing
    /// that targeting would weaken laws that currently bite.
    ///
    /// ## The gate is a naming convention, and that is load-bearing
    ///
    /// Every swift-syntax node type ends in `Syntax`. This is the one place a
    /// name-suffix test is sound rather than a heuristic: it is the library's
    /// own generated-code convention, not an inference about intent. The cost of
    /// a false positive is bounded and loud — a user type named `FooSyntax` gets
    /// a recipe that fails to compile against `SyntaxProtocol`, which reports as
    /// `build-failed` on that one entry rather than silently changing a verdict.
    ///
    /// A trailing `?` is unwrapped because `InheritanceClauseSyntax?` is a real
    /// surveyed carrier; collections are deliberately NOT unwrapped here, since
    /// `[CodeBlockItemSyntax]` and `ArraySlice<CodeBlockItemSyntax>` reach the
    /// kit through `GeneratorPlan.array` / `.arraySlice` over the element, which
    /// is the composite path's job rather than this one's.
    static func kitSyntaxNodeRecipe(carrier: String) -> GeneratorRecipe? {
        let bare = carrier.hasSuffix("?") ? String(carrier.dropLast()) : carrier
        guard bare.hasSuffix("Syntax"), !bare.contains("<"), !bare.contains("[") else { return nil }
        guard curatedSyntaxRecipes[bare] == nil else { return nil }
        return GeneratorRecipe(
            expression: "Gen<\(bare)>.syntaxNode()",
            carrierTypeName: bare,
            imports: syntaxImports + ["PropertyLawSyntax"]
        )
    }
}
