import Foundation
import SwiftParser
import SwiftSyntax

/// Swift source snippets a package's own tests feed to its parser — the domain a generated law
/// over a SwiftSyntax node draws from.
///
/// ## Why the tests, and why the source text
///
/// A stub whose subject takes a `FunctionDeclSyntax` cannot compile: no generator derives a
/// syntax node, and a random one would not be a meaningful input anyway. A tool that analyses
/// Swift code tests itself by parsing small snippets — SwiftProjectLint's test files call
/// `Parser.parse(source:)` 610 times over ~2,960 multi-line literals — so those snippets are
/// realistic by construction: code the authors wrote to exercise exactly these subjects.
///
/// `docs/measurements/corpus-domain-declined.md` tried the other route, mining the *values* tests
/// construct, and measured zero: nodes are obtained from a parse, never assembled in a `let` a
/// tool can capture. Harvesting the text the parse consumes is what that decline left open.
///
/// ## What counts as a snippet
///
/// A **multi-line** string literal with **no interpolation** that **parses without error**. The
/// first two keep assertion messages and templated fixtures out; the third keeps deliberately
/// malformed parser-error cases out, which swift-syntax's own suite is full of.
public enum SyntaxSnippetHarvester {

    /// The harvested snippets, deduplicated and in a stable order, and the node kinds they
    /// contain — so a generator is only offered for a type the corpus can actually produce.
    public struct Corpus: Sendable, Equatable {
        public let snippets: [String]
        /// Concrete node type names present (`"FunctionDeclSyntax"`), plus the base categories
        /// (`"DeclSyntax"`, `"ExprSyntax"`, …) and `"Syntax"` itself when any node is present.
        public let nodeTypeNames: Set<String>

        public init(snippets: [String], nodeTypeNames: Set<String>) {
            self.snippets = snippets
            self.nodeTypeNames = nodeTypeNames
        }
    }

    /// Harvest from every `.swift` file under `roots`, skipping build output and generated
    /// stubs. `limit` caps the corpus so the emitted file stays reviewable; `maxLength` drops a
    /// snippet too long to read as an example.
    public static func harvest(roots: [URL], limit: Int = 300, maxLength: Int = 1_500) -> Corpus {
        var seen: Set<String> = []
        var snippets: [String] = []
        for file in swiftFiles(under: roots) {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for literal in multiLineLiterals(in: source) where literal.count <= maxLength {
                guard seen.insert(literal).inserted, parsesCleanly(literal) else { continue }
                snippets.append(literal)
                if snippets.count == limit { return corpus(of: snippets) }
            }
        }
        return corpus(of: snippets)
    }

    /// Multi-line, interpolation-free string literals, as the text they represent.
    static func multiLineLiterals(in source: String) -> [String] {
        let collector = LiteralCollector(viewMode: .sourceAccurate)
        collector.walk(Parser.parse(source: source))
        return collector.found
    }

    static func parsesCleanly(_ snippet: String) -> Bool {
        !Parser.parse(source: snippet).hasError
    }

    static func corpus(of snippets: [String]) -> Corpus {
        let collector = KindCollector(viewMode: .sourceAccurate)
        for snippet in snippets { collector.walk(Parser.parse(source: snippet)) }
        return Corpus(snippets: snippets, nodeTypeNames: collector.names)
    }

    private static func swiftFiles(under roots: [URL]) -> [URL] {
        let skipped: Set<String> = [".build", ".git", "Generated", "checkouts", ".swiftinfer"]
        var files: [URL] = []
        for root in roots {
            guard let walker = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in walker {
                if skipped.contains(url.lastPathComponent) {
                    walker.skipDescendants()
                    continue
                }
                if url.pathExtension == "swift" { files.append(url) }
            }
        }
        // Path order, so the same tree yields the same corpus on every machine.
        return files.sorted { $0.path < $1.path }
    }

    private final class LiteralCollector: SyntaxVisitor {
        var found: [String] = []

        override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
            if node.openingQuote.tokenKind == .multilineStringQuote,
               let value = node.representedLiteralValue {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { found.append(trimmed) }
            }
            return .skipChildren
        }
    }

    private final class KindCollector: SyntaxAnyVisitor {
        var names: Set<String> = []

        override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
            names.insert("Syntax")
            names.insert(String(describing: node.syntaxNodeType))
            if node.is(DeclSyntax.self) { names.insert("DeclSyntax") }
            if node.is(ExprSyntax.self) { names.insert("ExprSyntax") }
            if node.is(StmtSyntax.self) { names.insert("StmtSyntax") }
            if node.is(TypeSyntax.self) { names.insert("TypeSyntax") }
            if node.is(PatternSyntax.self) { names.insert("PatternSyntax") }
            return .visitChildren
        }
    }
}
