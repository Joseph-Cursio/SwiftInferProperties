import Foundation

/// A closure's parameter clause — `rng`, `(value: T)`, `first, second` — and the body after its
/// `in`, so a break keeps the parameters beside the brace.
enum ClosureHead {

    /// The parameters and body of a closure's children, or an empty head and the children
    /// unchanged when there is no parameter clause.
    static func split(_ children: [LayoutNode]) -> (head: String, body: [LayoutNode]) {
        var head: [LayoutNode] = []
        for (index, node) in children.enumerated() {
            guard case .text(let text) = node, let range = keywordIn(text) else {
                head.append(node)
                continue
            }
            let signature = (head.flat + text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            guard isSignature(signature) else { break }
            let rest = String(text[range.upperBound...])
            let body = (rest.isEmpty ? [] : [LayoutNode.text(rest)]) + children[(index + 1)...]
            return (signature, body.trimmed)
        }
        return ("", children)
    }

    /// The first `in` in `text` that stands as a word.
    private static func keywordIn(_ text: String) -> Range<String.Index>? {
        var searchStart = text.startIndex
        while let range = text.range(of: "in", range: searchStart ..< text.endIndex) {
            let before = range.lowerBound == text.startIndex ? " " : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? " " : text[range.upperBound]
            if before == " ", after == " " { return range }
            searchStart = range.upperBound
        }
        return nil
    }

    static func isSignature(_ text: String) -> Bool {
        // Attributes (`@Sendable`), a capture list, then the parameters, effects and result type.
        let pattern = #"^(@\w+\s*)*(\[[^\]]*\]\s*)?"#
            + #"(_|\w+(\s*,\s*\w+)*|\(.*\))(\s+(async|throws|rethrows))*(\s*->\s*\S.*)?$"#
        return !text.isEmpty && text.range(of: pattern, options: .regularExpression) != nil
    }
}

/// Names for a closure's `$0`, `$1`, … once it has to span lines.
///
/// `shorthand_argument` refuses a `$n` more than four lines below its closure's brace, and a
/// memberwise generator's `.map { T(a: $0.0, b: $0.1, …) }` puts one per line when it breaks. So
/// a closure that breaks gets a parameter clause — `drawn`, or `drawn0, drawn1` — and each `$n`
/// at its own level becomes that name. A nested closure keeps its own `$n`; a `$n` inside a
/// string interpolation leaves the closure as it was, since the two spellings cannot be mixed.
enum ShorthandNames {

    static func naming(_ children: [LayoutNode]) -> (head: String, body: [LayoutNode])? {
        var used = Set<Int>()
        guard collect(children, into: &used), let highest = used.max() else { return nil }
        let taken = identifiers(in: children)
        guard let base = ["drawn", "element", "operand"].first(where: { candidate in
            !(0 ... highest).contains { taken.contains(name(candidate, $0, highest)) }
        }) else { return nil }
        let names = (0 ... highest).map { used.contains($0) ? name(base, $0, highest) : "_" }
        return (names.joined(separator: ", "), renaming(children, base: base, highest: highest))
    }

    private static func name(_ base: String, _ index: Int, _ highest: Int) -> String {
        highest == 0 ? base : "\(base)\(index)"
    }

    /// Every `$n` this closure owns; `false` when one sits inside a literal.
    ///
    /// A nested closure's `$n` are its own, but a nested *block* — an `if` body inside the
    /// closure — uses the closure's, so it is searched too.
    private static func collect(_ nodes: [LayoutNode], into used: inout Set<Int>) -> Bool {
        for (index, node) in nodes.enumerated() {
            switch node {
            case .text(let text):
                used.formUnion(shorthandIndices(in: text))

            case .literal(let text):
                if !shorthandIndices(in: text).isEmpty { return false }

            case .comment:
                continue

            case let .group(open, children, _):
                guard open != "{" || !opensClosure(nodes, at: index) else { continue }
                if !collect(children, into: &used) { return false }
            }
        }
        return true
    }

    /// Whether the brace at `index` opens a closure, read from the statement it belongs to.
    private static func opensClosure(_ nodes: [LayoutNode], at index: Int) -> Bool {
        var prefix: [LayoutNode] = []
        for node in nodes[..<index] {
            if case .text(let text) = node, let semicolon = text.lastIndex(of: ";") {
                prefix = [.text(String(text[text.index(after: semicolon)...]))]
            } else {
                prefix.append(node)
            }
        }
        return BraceBody.isClosure(prefix: prefix)
    }

    private static func shorthandIndices(in text: String) -> [Int] {
        var indices: [Int] = []
        var remaining = Substring(text)
        while let dollar = remaining.firstIndex(of: "$") {
            let digits = remaining[remaining.index(after: dollar)...].prefix { $0.isASCII && $0.isNumber }
            if let value = Int(digits) { indices.append(value) }
            remaining = remaining[remaining.index(after: dollar)...]
        }
        return indices
    }

    private static func identifiers(in nodes: [LayoutNode]) -> Set<String> {
        var names = Set<String>()
        for node in nodes {
            switch node {
            case .text(let text):
                names.formUnion(text.split { !($0.isLetter || $0.isNumber || $0 == "_") }.map(String.init))

            case let .group(_, children, _):
                names.formUnion(identifiers(in: children))

            case .literal, .comment:
                continue
            }
        }
        return names
    }

    /// `nodes` with each `$n` this closure owns spelled as its name — the same walk as `collect`.
    private static func renaming(_ nodes: [LayoutNode], base: String, highest: Int) -> [LayoutNode] {
        nodes.enumerated().map { index, node in
            switch node {
            case .text(let text):
                return .text(renamed(text, base: base, highest: highest))

            case let .group(open, children, close) where open != "{" || !opensClosure(nodes, at: index):
                return .group(open: open, children: renaming(children, base: base, highest: highest), close: close)

            default:
                return node
            }
        }
    }

    private static func renamed(_ text: String, base: String, highest: Int) -> String {
        var result = ""
        var remaining = Substring(text)
        while let dollar = remaining.firstIndex(of: "$") {
            result += remaining[..<dollar]
            let afterDollar = remaining.index(after: dollar)
            let digits = remaining[afterDollar...].prefix { $0.isASCII && $0.isNumber }
            if let value = Int(digits) {
                result += name(base, value, highest)
                remaining = remaining[digits.endIndex...]
            } else {
                result += "$"
                remaining = remaining[afterDollar...]
            }
        }
        return result + remaining
    }
}

/// A node list read as a chain: everything before its first `.call`, then each `.call` with any
/// property accesses after it.
struct ChainSegments {

    private(set) var head: [LayoutNode] = []
    private(set) var calls: [[LayoutNode]] = []

    init(_ nodes: [LayoutNode]) {
        var current: [LayoutNode] = []
        var previous: Character?
        for (index, node) in nodes.enumerated() {
            guard case .text(let text) = node else {
                current.append(node)
                previous = node.flat.last
                continue
            }
            var piece = ""
            for (offset, char) in text.enumerated() {
                let rest = text.dropFirst(offset + 1)
                if char == ".", Self.isMemberDot(after: previous, before: rest.first),
                   Self.isCall(Substring(rest), next: index + 1 < nodes.count ? nodes[index + 1] : nil) {
                    if !piece.isEmpty { current.append(.text(piece)) }
                    flushSegment(&current)
                    piece = ""
                }
                piece.append(char)
                previous = char
            }
            if !piece.isEmpty { current.append(.text(piece)) }
        }
        flushSegment(&current)
    }

    private mutating func flushSegment(_ current: inout [LayoutNode]) {
        if calls.isEmpty, head.isEmpty, !current.isEmpty, !Self.startsWithDot(current) {
            head = current
        } else if !current.isEmpty {
            calls.append(current)
        }
        current = []
    }

    private static func startsWithDot(_ nodes: [LayoutNode]) -> Bool {
        if case .text(let text)? = nodes.first { return text.hasPrefix(".") }
        return false
    }

    static func isMemberDot(after previous: Character?, before next: Character?) -> Bool {
        guard let previous, let next, next.isLetter || next == "_" else { return false }
        return previous.isLetter || previous.isNumber || ")]}>?!_\"".contains(previous)
    }

    /// Whether the member after a dot is called: its name runs to the end of the text node and
    /// an argument list or a trailing closure comes next.
    static func isCall(_ rest: Substring, next: LayoutNode?) -> Bool {
        let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        let after = rest.dropFirst(name.count)
        guard case let .group(open, _, _)? = next else { return false }
        return (open == "(" && after.isEmpty) || (open == "{" && after == " ")
    }
}
