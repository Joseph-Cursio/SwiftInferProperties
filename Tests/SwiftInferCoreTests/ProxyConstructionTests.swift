@testable import SwiftInferCore
import Testing

/// The proxy-construction recipe — the tier that stops a parser-constructed
/// carrier from dead-ending at "no strategy matched this type".
///
/// The gate is a suffix rule rather than a curated list of SwiftSyntax node
/// types, so most of these tests are about the **boundary**: what it must not
/// claim. A recipe that fired on the wrong carrier would hand a reader Swift
/// that does not compile, which is worse than the honest "not derived" it
/// replaces.
@Suite("Proxy construction — recipes for carriers that are parsed, not built")
struct ProxyConstructionTests {

    // MARK: - Recognised

    @Test(
        "concrete SwiftSyntax node types are parser-constructed",
        arguments: [
            "FunctionDeclSyntax", "ClosureExprSyntax", "StructDeclSyntax",
            "FunctionCallExprSyntax", "AccessorBlockSyntax", "SourceFileSyntax",
            "PatternBindingSyntax", "MemberBlockSyntax", "Syntax"
        ]
    )
    func recognisesNodeTypes(typeName: String) {
        #expect(ProxyConstruction.isParserConstructed(typeName))
        #expect(ProxyConstruction.recipe(subject: "node", typeName: typeName) != nil)
    }

    // MARK: - Boundary

    /// The generic spellings have no single concrete node to parse out, so the
    /// recipe could not name one and would be guessing.
    @Test(
        "generic and protocol spellings are declined",
        arguments: ["some SyntaxProtocol", "any SyntaxProtocol", "SyntaxProtocol", "[FunctionDeclSyntax]"]
    )
    func declinesGenericSpellings(typeName: String) {
        #expect(ProxyConstruction.isParserConstructed(typeName) == false)
        #expect(ProxyConstruction.recipe(subject: "node", typeName: typeName) == nil)
    }

    @Test(
        "ordinary carriers are untouched",
        arguments: ["String", "[LintIssue]", "FunctionSignature", "Int", "LintConfiguration"]
    )
    func declinesOrdinaryCarriers(typeName: String) {
        #expect(ProxyConstruction.isParserConstructed(typeName) == false)
    }

    /// The suffix rule keys on `Syntax`, so a user type that merely *ends* that
    /// way would be caught. Accepted deliberately — the alternative is a curated
    /// list that goes stale every SwiftSyntax release and fails silently — but
    /// pinned here so the trade-off is visible rather than discovered.
    @Test("a user type ending in Syntax is caught by the suffix rule — known trade-off")
    func suffixRuleIsNameBased() {
        #expect(ProxyConstruction.isParserConstructed("MyOwnSyntax"))
    }

    @Test("whitespace around the type name does not defeat the gate")
    func toleratesWhitespace() {
        #expect(ProxyConstruction.isParserConstructed("  FunctionDeclSyntax  "))
        let recipe = ProxyConstruction.recipe(subject: "node", typeName: "  FunctionDeclSyntax  ")
        #expect(recipe?.typeName == "FunctionDeclSyntax")
    }

    // MARK: - Recipe content

    /// The recipe is the product, so its content is worth asserting rather than
    /// just its existence.
    @Test("the recipe names the type, parses, and iterates the tree")
    func recipeIsRunnableShaped() throws {
        let recipe = try #require(
            ProxyConstruction.recipe(subject: "node", typeName: "ClosureExprSyntax")
        )
        #expect(recipe.subject == "node")
        #expect(recipe.typeName == "ClosureExprSyntax")

        // The three moves that make it runnable: generate source, parse it, walk it.
        #expect(recipe.expression.contains("Gen<String?>.element(of:"))
        #expect(recipe.expression.contains("Parser.parse(source: source)"))
        #expect(recipe.expression.contains("descendants(of: ClosureExprSyntax.self)"))
        // And the helper the reader has to paste once.
        #expect(recipe.expression.contains("func descendants<T: SyntaxProtocol>"))
    }

    /// Malformed fragments are load-bearing, not filler: totality is the law a
    /// predicate owes, and it is only tested by input that does not parse
    /// cleanly.
    @Test("the corpus keeps malformed source")
    func corpusRetainsMalformedFragments() {
        #expect(ProxyConstruction.sourceFragments.contains("func broken( {"))
        #expect(ProxyConstruction.sourceFragments.contains(""))
        let recipe = ProxyConstruction.recipe(subject: "node", typeName: "StructDeclSyntax")
        #expect(recipe?.expression.contains("func broken( {") == true)
    }

    /// The fragments are embedded as Swift string literals, so an unescaped
    /// quote would emit source that does not compile — the one way this feature
    /// could actively mislead.
    @Test("embedded fragments are escaped so the emitted recipe compiles")
    func fragmentsAreEscaped() {
        #expect(ProxyConstruction.quoted("a \"b\" c") == "\"a \\\"b\\\" c\"")
        #expect(ProxyConstruction.quoted("back\\slash") == "\"back\\\\slash\"")

        // The View fragment contains a quoted string; it must survive embedding.
        let recipe = ProxyConstruction.recipe(subject: "node", typeName: "StructDeclSyntax")
        #expect(recipe?.expression.contains(#"Text(\"hi\")"#) == true)
    }

    /// The rationale has to explain *why* parsing rather than building, or a
    /// reader will replace it with a hand-built node on the first cleanup pass —
    /// the same decay `CollisionBias` warns about for alphabets.
    @Test("the rationale argues the domain restriction, not just the mechanism")
    func rationaleExplainsWhyParsing() throws {
        let recipe = try #require(
            ProxyConstruction.recipe(subject: "node", typeName: "FunctionDeclSyntax")
        )
        #expect(recipe.rationale.contains("PARSED, not built"))
        #expect(recipe.rationale.contains("totality"))
    }
}
