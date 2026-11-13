import SwiftParser
import SwiftSyntax

/// Every harvested snippet with the token texts and node kinds it holds, so a stub's seeds can admit
/// the snippets that hold them (#684, `docs/plans/predicate-reach-at-source-scope.md` §2.3).
///
/// The test is at **snippet** level: a snippet is admitted when it holds a node of the requested type
/// and, anywhere, a seed token or a node of a seed kind. The emitted generator then matches at node
/// level, so a loose admission costs a few extra snippets in the file and nothing in the draw.
public struct SnippetIndex: Sendable {

    public struct Entry: Sendable, Equatable {
        public let snippet: String
        /// Every token's text, `tokens(viewMode: .sourceAccurate)`.
        public let tokens: Set<String>
        /// The same kind names `SyntaxSnippetHarvester.Corpus.nodeTypeNames` uses, categories included.
        public let kinds: Set<String>
    }

    public let entries: [Entry]

    public init(snippets: [String]) {
        entries = snippets.map { snippet in
            let tree = Parser.parse(source: snippet)
            let collector = SyntaxSnippetHarvester.KindCollector(viewMode: .sourceAccurate)
            collector.walk(tree)
            return Entry(
                snippet: snippet,
                tokens: Set(tree.tokens(viewMode: .sourceAccurate).map(\.text)),
                kinds: collector.names
            )
        }
    }

    /// The entries holding a `nodeType` node and a seed, in harvest order.
    public func matching(nodeType: String, seeds: SyntaxSeeds) -> [Entry] {
        let tokens = Set(seeds.tokens)
        let kinds = Set(seeds.kinds)
        return entries.filter { entry in
            entry.kinds.contains(nodeType)
                && (!entry.tokens.isDisjoint(with: tokens) || !entry.kinds.isDisjoint(with: kinds))
        }
    }
}
