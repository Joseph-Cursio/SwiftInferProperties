/// The emitted corpus's #684 half and its literal helper, beside `SyntaxCorpusSource`, whose body would
/// otherwise cross SwiftLint's length cap.
extension SyntaxCorpusSource {

    /// `["a", "b"]`. Seed tokens hold no whitespace (`SyntaxSeeds.isTokenLike`), so a backslash and a
    /// quote are all there is to escape.
    static func arrayLiteral(_ values: [String]) -> String {
        let quoted = values.map { value in
            "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        return "[" + quoted.joined(separator: ", ") + "]"
    }

    /// The #684 half, emitted under every arm but the pure baseline (`ReachArm.needsReachMachinery`):
    /// a draw biased toward the nodes a subject compares against, and a name taken from a drawn node
    /// for relational pairing. Raw, so the interpolations inside it stay in the emitted file.
    static let reachMachinery = #"""
            /// Whether `node` holds a token whose text is in `tokens`, or it, an ancestor or a
            /// descendant is of a kind named in `kinds`.
            static func matches(_ node: Syntax, tokens: Set<String>, kinds: Set<String>) -> Bool {
                let held = node.tokens(viewMode: .sourceAccurate)
                if !tokens.isEmpty, held.contains(where: { tokens.contains($0.text) }) {
                    return true
                }
                guard !kinds.isEmpty else { return false }
                var current: Syntax? = node
                while let ancestor = current {
                    if kinds.contains(String(describing: ancestor.syntaxNodeType)) { return true }
                    current = ancestor.parent
                }
                let finder = KindFinder(kinds: kinds)
                finder.walk(node)
                return finder.found
            }

            private final class KindFinder: SyntaxAnyVisitor {
                let kinds: Set<String>
                var found = false

                init(kinds: Set<String>) {
                    self.kinds = kinds
                    super.init(viewMode: .sourceAccurate)
                }

                override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
                    if !found, kinds.contains(String(describing: node.syntaxNodeType)) { found = true }
                    return found ? .skipChildren : .visitChildren
                }
            }

            private struct MatchKey: Hashable {
                let type: ObjectIdentifier
                let tokens: Set<String>
                let kinds: Set<String>
            }

            private final class MatchCache: @unchecked Sendable {
                private let lock = NSLock()
                private var storage: [MatchKey: Any] = [:]

                func nodes<Node: SyntaxProtocol>(_ key: MatchKey, build: () -> [Node]) -> [Node] {
                    lock.lock()
                    defer { lock.unlock() }
                    if let hit = storage[key] as? [Node] { return hit }
                    let built = build()
                    storage[key] = built
                    return built
                }
            }

            private static let matchCache = MatchCache()

            /// A generator drawing, half the time, among the `Node`s that match — what the subject
            /// compares against — and otherwise among every `Node`. With none matching it draws
            /// among every `Node`, as `gen(_:)` does.
            ///
            /// ⚠ **The result type is spelled, not `some`.** A stub whose draw line is long hoists its
            /// generator into a `static let`, and a stored property cannot infer a type involving
            /// another declaration's opaque result. The seed lists make this draw long, so it is
            /// hoisted more often than `gen(_:)`; it does not shrink, which totality never asks of it.
            static func gen<Node: SyntaxProtocol>(
                _ type: Node.Type,
                preferring tokens: Set<String>,
                kinds: Set<String>
            ) -> Generator<Node, Shrink.None<Node>> {
                let all = nodes(type)
                let key = MatchKey(type: ObjectIdentifier(type), tokens: tokens, kinds: kinds)
                let matching = matchCache.nodes(key) {
                    all.filter { matches(Syntax($0), tokens: tokens, kinds: kinds) }
                }
                let preferred = matching.isEmpty ? all : matching
                return Generator { rng in
                    let pool = rng.next() & 1 == 0 ? preferred : all
                    return pool[Int(rng.next() % UInt64(max(pool.count, 1)))]
                }
            }

            /// An identifier or keyword token's text from `node`'s subtree or, one time in three,
            /// from its whole tree — a name a relational predicate might look for. `nil` when there
            /// is none.
            static func name<Node: SyntaxProtocol, R: RandomNumberGenerator>(
                near node: Node,
                using rng: inout R
            ) -> String? {
                let scope = Int.random(in: 0 ..< 3, using: &rng) == 0 ? Syntax(node).root : Syntax(node)
                let names = scope.tokens(viewMode: .sourceAccurate).compactMap { token -> String? in
                    switch token.tokenKind {
                    case .identifier, .keyword:
                        return token.text

                    default:
                        return nil
                    }
                }
                guard !names.isEmpty else { return nil }
                return names[Int.random(in: 0 ..< names.count, using: &rng)]
            }
    """#
}
