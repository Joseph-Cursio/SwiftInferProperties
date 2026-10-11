/// One logical line of generated Swift, read as the brackets, string literals and block comments
/// a re-layout has to respect — see `GeneratedFileLayout`.
///
/// Deliberately not a syntax tree. A layout only ever inserts a line break immediately after an
/// opening bracket, after a comma or a `;`, or immediately before a closing bracket, and none of
/// those positions can change what Swift parses; so the bracket structure is the whole of what it
/// needs to know. What it must never do is look inside a string literal or a comment, which is
/// why those are opaque leaves here.
indirect enum LayoutNode: Equatable, Sendable {
    case text(String)
    /// A complete single-line string literal, quotes included.
    case literal(String)
    /// A complete `/* … */` comment.
    case comment(String)
    case group(open: Character, children: [Self], close: Character)

    var flat: String {
        switch self {
        case .text(let text), .literal(let text), .comment(let text):
            return text

        case let .group(open, children, close):
            return String(open) + children.flat + String(close)
        }
    }
}

extension Array where Element == LayoutNode {

    var flat: String { map(\.flat).joined() }

    /// `self` without whitespace at either end, so an element split out of a list starts and ends
    /// on its own content.
    var trimmed: [LayoutNode] {
        var nodes = self
        while case .text(let text)? = nodes.first {
            let kept = String(text.drop { $0 == " " })
            if kept.isEmpty { nodes.removeFirst() } else { nodes[0] = .text(kept); break }
        }
        while case .text(let text)? = nodes.last {
            let kept = String(text.reversed().drop { $0 == " " }.reversed())
            if kept.isEmpty { nodes.removeLast() } else { nodes[nodes.count - 1] = .text(kept); break }
        }
        return nodes
    }

    /// `self` split wherever `separator` appears in a top-level text node — commas between the
    /// elements of a list, semicolons between the statements of a body. A separator inside a
    /// nested group or a literal is not top-level and does not split.
    func split(on separator: Character) -> [[LayoutNode]] {
        var parts: [[LayoutNode]] = [[]]
        for node in self {
            guard case .text(let text) = node, text.contains(separator) else {
                parts[parts.count - 1].append(node)
                continue
            }
            let pieces = text.split(separator: separator, omittingEmptySubsequences: false)
            for (offset, piece) in pieces.enumerated() {
                if offset > 0 { parts.append([]) }
                if !piece.isEmpty { parts[parts.count - 1].append(.text(String(piece))) }
            }
        }
        return parts.map(\.trimmed)
    }
}

/// Reads one logical line into `LayoutNode`s, or answers `nil` when it holds something a layout
/// must not touch: unbalanced brackets, a raw or multi-line string, or a `//` comment.
struct LayoutParser {

    private let chars: [Character]
    private var index = 0
    private var stack: [(open: Character, children: [LayoutNode])] = [(" ", [])]
    private var pending = ""

    static func nodes(_ source: String) -> [LayoutNode]? {
        var parser = Self(chars: Array(source))
        return parser.parse()
    }

    private init(chars: [Character]) {
        self.chars = chars
    }

    private mutating func parse() -> [LayoutNode]? {
        while index < chars.count {
            guard step() else { return nil }
        }
        flush()
        guard stack.count == 1 else { return nil }
        return stack[0].children
    }

    /// Consumes one token, answering `false` for anything the layout refuses to read.
    private mutating func step() -> Bool {
        let char = chars[index]
        switch char {
        case "\"":
            guard let end = Self.literalEnd(in: chars, from: index) else { return false }
            append(.literal(String(chars[index ..< end])))
            index = end

        case "#" where peek(1) == "\"":
            return false

        case "/" where peek(1) == "/":
            return false

        case "/" where peek(1) == "*":
            guard let end = Self.blockCommentEnd(in: chars, from: index) else { return false }
            append(.comment(String(chars[index ..< end])))
            index = end

        case "(", "[", "{":
            flush()
            stack.append((char, []))
            index += 1

        case ")", "]", "}":
            return close(char)

        default:
            pending.append(char)
            index += 1
        }
        return true
    }

    private mutating func close(_ char: Character) -> Bool {
        flush()
        guard stack.count > 1, Self.closer(of: stack[stack.count - 1].open) == char else { return false }
        let finished = stack.removeLast()
        stack[stack.count - 1].children.append(.group(open: finished.open, children: finished.children, close: char))
        index += 1
        return true
    }

    private func peek(_ offset: Int) -> Character? {
        index + offset < chars.count ? chars[index + offset] : nil
    }

    private mutating func append(_ node: LayoutNode) {
        flush()
        stack[stack.count - 1].children.append(node)
    }

    private mutating func flush() {
        guard !pending.isEmpty else { return }
        stack[stack.count - 1].children.append(.text(pending))
        pending = ""
    }

    static func closer(of open: Character) -> Character {
        switch open {
        case "(": return ")"
        case "[": return "]"
        default: return "}"
        }
    }

    /// The index just past the single-line string literal opening at `start`, or `nil` for a
    /// multi-line delimiter or an unterminated literal. Interpolations are walked so a `"` or `)`
    /// inside `\( … )` cannot end the literal early.
    static func literalEnd(in chars: [Character], from start: Int) -> Int? {
        if start + 2 < chars.count, chars[start + 1] == "\"", chars[start + 2] == "\"" { return nil }
        var cursor = start + 1
        while cursor < chars.count {
            switch chars[cursor] {
            case "\"":
                return cursor + 1

            case "\\" where cursor + 1 < chars.count && chars[cursor + 1] == "(":
                guard let end = interpolationEnd(in: chars, from: cursor + 1) else { return nil }
                cursor = end

            case "\\":
                cursor += 2

            default:
                cursor += 1
            }
        }
        return nil
    }

    /// The index just past the `)` closing the interpolation whose `(` is at `open`.
    static func interpolationEnd(in chars: [Character], from open: Int) -> Int? {
        var depth = 0
        var cursor = open
        while cursor < chars.count {
            switch chars[cursor] {
            case "(":
                depth += 1
                cursor += 1

            case ")":
                depth -= 1
                cursor += 1
                if depth == 0 { return cursor }

            case "\"":
                guard let end = literalEnd(in: chars, from: cursor) else { return nil }
                cursor = end

            default:
                cursor += 1
            }
        }
        return nil
    }

    /// The index just past the `*/` closing the block comment at `start`, nesting as Swift does.
    static func blockCommentEnd(in chars: [Character], from start: Int) -> Int? {
        var depth = 0
        var cursor = start
        while cursor + 1 < chars.count {
            if chars[cursor] == "/", chars[cursor + 1] == "*" {
                depth += 1
                cursor += 2
            } else if chars[cursor] == "*", chars[cursor + 1] == "/" {
                depth -= 1
                cursor += 2
                if depth == 0 { return cursor }
            } else {
                cursor += 1
            }
        }
        return nil
    }
}
