/// A `/* … */` comment too long for its line, continued over several. Swift reads a block
/// comment that spans lines as the whitespace it replaces, so this is the one break a comment
/// inside an expression can take — the `.todo` marker a stub carries where no generator derived,
/// `Foo.gen() /* … no generator derived — … */`, runs to 600 characters.
enum CommentContinuation {

    static func lines(for nodes: [LayoutNode], indent: Int, limit: Int) -> [String]? {
        guard let index = nodes.firstIndex(where: { if case .comment = $0 { true } else { false } }),
              case .comment(let text) = nodes[index] else { return nil }
        var words = text.split(separator: " ").map(String.init)
        guard words.count > 1 else { return nil }
        words[0] = Array(nodes[..<index]).flat + words[0]
        words[words.count - 1] += Array(nodes[(index + 1)...]).flat
        let pad = String(repeating: " ", count: indent)
        let continuation = pad + "   "
        var result: [String] = []
        var current = ""
        for word in words {
            if current.isEmpty {
                current = pad + word
            } else if current.count + 1 + word.count > limit {
                result.append(current)
                current = continuation + word
            } else {
                current += " " + word
            }
        }
        return result + [current]
    }
}
