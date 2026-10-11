/// The line-level half of `GeneratedFileLayout`: comments and multi-line string content wrapped
/// at a space, and blank lines collapsed — none of which needs the bracket structure.
enum GeneratedFileText {

    /// A comment-only line over the limit, wrapped at spaces onto lines with the same `//` and the
    /// same indentation after it.
    ///
    /// `// Source:` is left whole: the path after it is read back by tools that match the line
    /// as `// Source: <path>:<line>` (`scripts/mutation_check.py`, the funnel censuses), and
    /// splitting it at the one space it has would leave the path on a line of its own.
    static func wrappingLongComments(_ lines: [String]) -> [String] {
        let scan = GeneratedFileScan(lines)
        return lines.enumerated().flatMap { number, line -> [String] in
            guard scan.lines[number].commentOnly, !scan.lines[number].frozen,
                  line.count > GeneratedFileLayout.lineLimit else { return [line] }
            return wrappedComment(line)
        }
    }

    static func wrappedComment(_ line: String) -> [String] {
        let indent = String(line.prefix { $0 == " " })
        let afterIndent = line.dropFirst(indent.count)
        let marker = afterIndent.hasPrefix("///") ? "///" : "//"
        let afterMarker = afterIndent.dropFirst(marker.count)
        let hang = String(afterMarker.prefix { $0 == " " })
        let text = afterMarker.dropFirst(hang.count)
        guard !text.hasPrefix("Source: ") else { return [line] }
        let prefix = indent + marker + (hang.isEmpty ? " " : hang)
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map { String($0) + " " }
        let chunks = LiteralContinuation.wrapped(words: words, width: GeneratedFileLayout.lineLimit - prefix.count + 1)
        guard chunks.count > 1 else { return [line] }
        return chunks.map { prefix + $0.trimmingCharacters(in: .whitespaces) }
    }

    /// A content line of a multi-line string literal over the limit, continued onto the next line
    /// with `\` at a space. The continuation carries exactly the closing delimiter's indentation,
    /// which Swift strips, so the literal's value does not change. Raw literals, where `\` is
    /// text, are left alone.
    static func wrappingLongLiteralContent(_ lines: [String]) -> [String] {
        let scan = GeneratedFileScan(lines)
        var closingIndent: [Int: Int] = [:]
        for literal in scan.literals where !literal.isRaw {
            for line in literal.contentLines { closingIndent[line] = literal.closingIndent }
        }
        return lines.enumerated().flatMap { number, line -> [String] in
            guard let indent = closingIndent[number], line.count > GeneratedFileLayout.lineLimit,
                  line.prefix(indent).allSatisfy({ $0 == " " }) else { return [line] }
            return continuedContent(line, indent: indent)
        }
    }

    static func continuedContent(_ line: String, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        let words = LiteralContinuation.words(in: Array(line.dropFirst(indent)))
        let chunks = LiteralContinuation.wrapped(words: words, width: GeneratedFileLayout.lineLimit - indent - 1)
        guard chunks.count > 1 else { return [line] }
        return chunks.enumerated().map { offset, chunk in
            pad + chunk + (offset < chunks.count - 1 ? "\\" : "")
        }
    }

    /// No trailing whitespace, no run of blank lines, no blank line at the top, and exactly one
    /// newline at the end — outside a multi-line literal, whose blank lines and trailing spaces
    /// are part of its value.
    static func collapsingBlankLines(_ lines: [String]) -> [String] {
        let scan = GeneratedFileScan(lines)
        var result: [String] = []
        for (number, line) in lines.enumerated() {
            if scan.lines[number].frozen {
                result.append(line)
                continue
            }
            let stripped = String(line.reversed().drop { $0 == " " }.reversed())
            if stripped.isEmpty, result.last?.isEmpty ?? true { continue }
            result.append(stripped)
        }
        while result.last?.isEmpty == true { result.removeLast() }
        return result + [""]
    }
}
