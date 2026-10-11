/// What `GeneratedFileLayout` needs to know about each physical line of a generated file before
/// it may re-lay any of them out: which lines belong to a multi-line string or comment (and are
/// therefore text, not code), and where every bracket pair opens and closes.
struct GeneratedFileScan {

    struct LineFacts {
        /// Inside, or delimiting, a multi-line string literal or a multi-line block comment.
        var frozen = false
        var commentOnly = false
        /// A `//` comment after code. A region holding one cannot be flattened onto one line.
        var trailingComment = false
    }

    struct Group {
        let open: Character
        let openLine: Int
        let openColumn: Int
        let closeLine: Int
        /// Whether the closer is the first thing on its line.
        let closeLeads: Bool
    }

    /// A multi-line string literal: the content lines between its delimiters, and the indentation
    /// of its closing delimiter, which is the indentation Swift strips from every content line.
    struct MultilineLiteral {
        let contentLines: Range<Int>
        let closingIndent: Int
        let isRaw: Bool
    }

    private(set) var lines: [LineFacts]
    private(set) var groups: [Group] = []
    private(set) var literals: [MultilineLiteral] = []
    /// `false` when a closer matched no opener — the file is not one a layout should touch.
    private(set) var balanced = true

    private struct Opener {
        let char: Character
        let line: Int
        let column: Int
    }

    private var stack: [Opener] = []
    private var literalStart: (line: Int, hashes: Int)?
    private var commentDepth = 0

    init(_ source: [String]) {
        lines = Array(repeating: LineFacts(), count: source.count)
        for (number, line) in source.enumerated() {
            scan(Array(line), line: number)
        }
        if !stack.isEmpty || literalStart != nil || commentDepth > 0 { balanced = false }
    }

    static func indent(of line: String) -> Int {
        line.prefix { $0 == " " }.count
    }

    private mutating func scan(_ chars: [Character], line: Int) {
        var cursor = 0
        if literalStart != nil || commentDepth > 0 {
            lines[line].frozen = true
            guard let resumed = resume(chars, line: line) else { return }
            cursor = resumed
        }
        let leading = chars.prefix { $0 == " " }.count
        if chars.dropFirst(leading).starts(with: ["/", "/"]) {
            lines[line].commentOnly = true
            return
        }
        while cursor < chars.count {
            guard let next = scanToken(chars, at: cursor, line: line, leading: leading) else { return }
            cursor = next
        }
    }

    /// Continue a multi-line literal or comment opened on an earlier line, answering where code
    /// resumes on this line, or `nil` when the whole line is still inside it.
    private mutating func resume(_ chars: [Character], line: Int) -> Int? {
        if commentDepth > 0 {
            return resumeComment(chars)
        }
        guard let start = literalStart else { return nil }
        let delimiter = Array(repeating: Character("\""), count: 3) + Array(repeating: "#", count: start.hashes)
        let leading = chars.prefix { $0 == " " }.count
        guard chars.dropFirst(leading).starts(with: delimiter) else { return nil }
        literals.append(MultilineLiteral(
            contentLines: (start.line + 1) ..< line, closingIndent: leading, isRaw: start.hashes > 0
        ))
        literalStart = nil
        return leading + delimiter.count
    }

    private mutating func resumeComment(_ chars: [Character]) -> Int? {
        var cursor = 0
        while cursor + 1 < chars.count {
            if chars[cursor] == "*", chars[cursor + 1] == "/" {
                commentDepth -= 1
                cursor += 2
                if commentDepth == 0 { return cursor }
            } else if chars[cursor] == "/", chars[cursor + 1] == "*" {
                commentDepth += 1
                cursor += 2
            } else {
                cursor += 1
            }
        }
        return nil
    }

    /// One token of code at `cursor`; `nil` when the rest of the line is not code.
    private mutating func scanToken(_ chars: [Character], at cursor: Int, line: Int, leading: Int) -> Int? {
        switch chars[cursor] {
        case "#", "\"":
            return scanLiteral(chars, at: cursor, line: line)

        case "/" where cursor + 1 < chars.count && chars[cursor + 1] == "/":
            lines[line].trailingComment = true
            return nil

        case "/" where cursor + 1 < chars.count && chars[cursor + 1] == "*":
            if let end = LayoutParser.blockCommentEnd(in: chars, from: cursor) { return end }
            commentDepth = 1
            lines[line].frozen = true
            return nil

        case "(", "[", "{":
            stack.append(Opener(char: chars[cursor], line: line, column: cursor))
            return cursor + 1

        case ")", "]", "}":
            closeGroup(chars[cursor], line: line, leads: cursor == leading)
            return cursor + 1

        default:
            return cursor + 1
        }
    }

    private mutating func scanLiteral(_ chars: [Character], at cursor: Int, line: Int) -> Int? {
        let hashes = chars[cursor...].prefix { $0 == "#" }.count
        let quote = cursor + hashes
        guard quote < chars.count, chars[quote] == "\"" else { return cursor + max(hashes, 1) }
        if quote + 2 < chars.count, chars[quote + 1] == "\"", chars[quote + 2] == "\"" {
            literalStart = (line, hashes)
            lines[line].frozen = true
            return nil
        }
        if hashes == 0, let end = LayoutParser.literalEnd(in: chars, from: quote) { return end }
        // A raw single-line literal: skip to its `"` + the same number of `#`s.
        let closing = ["\""] + Array(repeating: Character("#"), count: hashes)
        var probe = quote + 1
        while probe + closing.count <= chars.count {
            if Array(chars[probe ..< probe + closing.count]) == closing { return probe + closing.count }
            probe += 1
        }
        lines[line].frozen = true
        return nil
    }

    private mutating func closeGroup(_ char: Character, line: Int, leads: Bool) {
        guard let opened = stack.popLast(), LayoutParser.closer(of: opened.char) == char else {
            balanced = false
            return
        }
        groups.append(Group(
            open: opened.char, openLine: opened.line, openColumn: opened.column, closeLine: line, closeLeads: leads
        ))
    }
}
