@testable import SwiftInferCore
import Testing

/// What a predicate over a syntax node compares against (#684). The fixtures are shapes from #665's red
/// rows, read by hand in `docs/plans/predicate-reach-at-source-scope.md` §1.
@Suite("SyntaxSeeds — the tokens and kinds a predicate's body compares against")
struct SyntaxSeedsTests {

    @Test("a token's text compared to a literal, and a keyword's case")
    func literalsAndKeywords() {
        let source = """
        enum ModuleScanner {
            static func hasGenMethod(_ decl: FunctionDeclSyntax) -> Bool {
                decl.name.text == "gen" && decl.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
            }
        }
        """
        let seeds = SyntaxSeeds.harvest(declarationAt: 2, in: source)
        #expect(seeds.tokens == ["gen", "static"])
        #expect(seeds.kinds.isEmpty)
    }

    /// `isAddTaskCall` compares against a file-private set it names; the body holds no literal.
    @Test("a same-file string set the body names, one hop away")
    func oneHopTable() {
        let source = """
        private let addTaskCallNames: Set<String> = ["addTask", "addTaskUnlessCancelled"]
        private let unrelated = ["never"]

        struct Walker {
            static let groupNames = Set(["withTaskGroup", "withThrowingTaskGroup"])

            func isAddTaskCall(_ call: FunctionCallExprSyntax) -> Bool {
                addTaskCallNames.contains(call.calledExpression.trimmedDescription)
                    || Self.groupNames.contains("x")
            }
        }
        """
        let seeds = SyntaxSeeds.harvest(declarationAt: 7, in: source)
        #expect(seeds.tokens == ["addTask", "addTaskUnlessCancelled", "withTaskGroup", "withThrowingTaskGroup", "x"])
    }

    @Test("a node kind tested by is, as or cast")
    func kinds() {
        let source = """
        struct V {
            func isAwaited(_ node: ExprSyntax) -> Bool {
                node.parent?.is(AwaitExprSyntax.self) == true
                    || node.as(KeyPathExprSyntax.self) != nil
                    || node.is(Int.self)
            }
        }
        """
        let seeds = SyntaxSeeds.harvest(declarationAt: 2, in: source)
        #expect(seeds.kinds == ["AwaitExprSyntax", "KeyPathExprSyntax"])
    }

    /// A literal with whitespace can never equal one token's text, and an interpolation has no value.
    @Test("prose and interpolations are not tokens")
    func proseIsNotAToken() {
        let source = #"""
        struct V {
            func f(_ name: String) -> Bool {
                name == "two words" || name == "\(name)x" || name == "ObservableObject"
            }
        }
        """#
        #expect(SyntaxSeeds.harvest(declarationAt: 2, in: source).tokens == ["ObservableObject"])
    }

    /// Review finding: a category never equals a concrete node's type, and every snippet holds one.
    @Test("a base category is not a seed kind, and a control character is not a token")
    func categoriesAndControls() {
        let source = #"""
        struct V {
            func f(_ node: Syntax) -> Bool {
                node.is(ExprSyntax.self) || node.is(TryExprSyntax.self) || node.description == "\u{7}"
            }
        }
        """#
        let seeds = SyntaxSeeds.harvest(declarationAt: 2, in: source)
        #expect(seeds.kinds == ["TryExprSyntax"])
        #expect(seeds.tokens.isEmpty)
    }

    @Test("no covering declaration reads nothing")
    func noDeclaration() {
        #expect(SyntaxSeeds.harvest(declarationAt: 40, in: "struct S {}").isEmpty)
    }

    @Test("each list is deduplicated and capped")
    func capped() {
        let names = (0 ..< 30).map { "\"t\($0)\"" }.joined(separator: ", ")
        let source = "func f(_ s: String) -> Bool { [\(names), \"t0\"].contains(s) }"
        let seeds = SyntaxSeeds.harvest(declarationAt: 1, in: source)
        #expect(seeds.tokens.count == SyntaxSeeds.cap)
        #expect(seeds.tokens.first == "t0")
        #expect(Set(seeds.tokens).count == seeds.tokens.count)
    }

    @Test("the snippet index admits a snippet holding the node type and a seed")
    func snippetIndex() {
        let index = SnippetIndex(snippets: [
            "class A: ObservableObject {}",
            "class B {}",
            "struct C: ObservableObject {}",
            "func f() async { await g() }",
        ])
        let byToken = index.matching(nodeType: "ClassDeclSyntax", seeds: SyntaxSeeds(tokens: ["ObservableObject"]))
        #expect(byToken.map(\.snippet) == ["class A: ObservableObject {}"])
        let byKind = index.matching(nodeType: "ExprSyntax", seeds: SyntaxSeeds(kinds: ["AwaitExprSyntax"]))
        #expect(byKind.map(\.snippet) == ["func f() async { await g() }"])
    }
}
