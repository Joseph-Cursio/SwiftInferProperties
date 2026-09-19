import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Generators for SwiftSyntax node parameters come from the package's test snippets.
@Suite("Syntax corpus — generators for SwiftSyntax nodes")
struct SyntaxCorpusSourceTests {

    private static func source() -> SyntaxCorpusSource {
        SyntaxCorpusSource(corpus: SyntaxSnippetHarvester.Corpus(
            snippets: ["func f() {}"],
            nodeTypeNames: ["Syntax", "FunctionDeclSyntax", "DeclSyntax"]
        ))
    }

    @Test("a node type the corpus contains draws from it")
    func presentType() {
        #expect(Self.source().generator(for: "FunctionDeclSyntax")
            == "SwiftInferSyntaxCorpus.gen(FunctionDeclSyntax.self)")
    }

    /// Offering a type the corpus lacks would compile and then trap on an empty range.
    @Test("a node type the corpus lacks is not offered")
    func absentType() {
        #expect(Self.source().generator(for: "ClassDeclSyntax") == nil)
        #expect(Self.source().generator(for: "String") == nil)
    }

    @Test("an array of nodes composes from the corpus generator")
    func arrayOfNodes() throws {
        let source = Self.source()
        let generator = InteractiveTriage.projectTypeGenerator(types: [], syntaxNode: source.generator(for:))
        let expression = try #require(generator("[FunctionDeclSyntax]"))
        #expect(expression.contains("SwiftInferSyntaxCorpus.gen(FunctionDeclSyntax.self)"))
        #expect(!expression.contains("no generator derived"))
    }

    /// A scanned type keeps its derived generator even when its name looks like a node type.
    @Test("a project type wins over the corpus")
    func projectTypeWins() throws {
        let source = SyntaxCorpusSource(corpus: SyntaxSnippetHarvester.Corpus(
            snippets: [], nodeTypeNames: ["WidgetSyntax"]
        ))
        let widget = TypeShape(
            name: "WidgetSyntax", kind: .struct, inheritedTypes: [], hasUserGen: false,
            storedMembers: [StoredMember(name: "count", typeName: "Int")]
        )
        let generator = InteractiveTriage.projectTypeGenerator(types: [widget], syntaxNode: source.generator(for:))
        let expression = try #require(generator("WidgetSyntax"))
        #expect(!expression.contains("SwiftInferSyntaxCorpus"))
    }

    @Test("raw delimiters outgrow anything in the snippet", arguments: [
        ("plain", 1), ("ends \"\"\"#", 2), ("escape \\#( x )", 2), ("\"\"\"## and \\#", 3)
    ])
    func rawDelimiters(snippet: String, expected: Int) {
        #expect(SyntaxCorpusSource.rawDelimiterCount(for: snippet) == expected)
    }

    @Test("the corpus file carries every snippet as a raw literal")
    func fileContents() {
        let text = SyntaxCorpusSource.fileContents(snippets: ["func f() {}", "let s = \"\"\"#"])
        #expect(text.contains("#\"\"\"\nfunc f() {}\n\"\"\"#"))
        #expect(text.contains("##\"\"\"\nlet s = \"\"\"#\n\"\"\"##"))
        #expect(text.contains("enum SwiftInferSyntaxCorpus"))
    }
}
