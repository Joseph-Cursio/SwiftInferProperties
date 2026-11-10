/// A single-line string literal too long for its line, continued over several with `\` inside a
/// multi-line literal. The value is unchanged: a `\` at the end of a content line joins it to the
/// next, and every content line carries exactly the closing delimiter's indentation, which Swift
/// strips.
enum LiteralContinuation {

    static func lines(for nodes: [LayoutNode], indent: Int, limit: Int) -> [String]? {
        guard case .literal(let literal)? = nodes.first, nodes.count <= 2,
              literal.hasPrefix("\""), !literal.hasPrefix("\"\"\""), literal.count >= 2 else { return nil }
        var trailing = ""
        if nodes.count == 2 {
            guard case .text(let text) = nodes[1], text.allSatisfy({ ",)]".contains($0) }) else { return nil }
            trailing = text
        }
        let content = String(literal.dropFirst().dropLast())
        guard !content.hasSuffix(" ") else { return nil }
        let pad = String(repeating: " ", count: indent)
        let chunks = wrapped(words: words(in: Array(content)), width: limit - indent - 1)
        let body = chunks.enumerated().map { offset, chunk in
            pad + chunk + (offset < chunks.count - 1 ? "\\" : "")
        }
        return [pad + "\"\"\""] + body + [pad + "\"\"\"" + trailing]
    }

    /// `chars` split after each space that is not inside an escape or an interpolation.
    static func words(in chars: [Character]) -> [String] {
        var words: [String] = []
        var current = ""
        var cursor = 0
        while cursor < chars.count {
            var end = cursor + 1
            if chars[cursor] == "\\", cursor + 1 < chars.count {
                end = cursor + 2
                if chars[cursor + 1] == "(" {
                    end = LayoutParser.interpolationEnd(in: chars, from: cursor + 1) ?? chars.count
                }
            }
            current += String(chars[cursor ..< end])
            if chars[cursor] == " " {
                words.append(current)
                current = ""
            }
            cursor = end
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// `words` packed greedily into lines of at most `width` characters; a word longer than
    /// `width` gets a line of its own.
    static func wrapped(words: [String], width: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in words {
            if !current.isEmpty, current.count + word.count > width {
                lines.append(current)
                current = ""
            }
            current += word
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}
