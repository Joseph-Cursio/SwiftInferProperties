/// Breaks one flattened line of Swift into lines that fit `limit`, the way SwiftLint's default
/// and commonly enabled rules want them: one argument or element per line with the closer back
/// at the opening line's indentation (`closure_end_indentation`,
/// `vertical_parameter_alignment_on_call`), a closure's parameters kept beside its brace
/// (`closure_parameter_position`), and a chain of two or more calls broken before every `.`
/// (`multiline_function_chains`).
///
/// Recursive: each piece a break produces is laid out again, so the outermost bracket breaks
/// first and an inner one only when its own line still does not fit.
struct LayoutBreaker {

    let limit: Int
    let indentWidth: Int

    func lines(for nodes: [LayoutNode], indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        if fits(nodes, indent: indent) { return [pad + nodes.flat] }
        if let chain = chainLines(nodes, indent: indent) { return chain }
        if let broken = groupLines(nodes, indent: indent) { return broken }
        if let literal = LiteralContinuation.lines(for: nodes, indent: indent, limit: limit) { return literal }
        if let comment = CommentContinuation.lines(for: nodes, indent: indent, limit: limit) { return comment }
        return [pad + nodes.flat]
    }

    /// Fits on one line — and holds no body of two or more statements, which reads as one line
    /// only by joining them with `;`.
    func fits(_ nodes: [LayoutNode], indent: Int) -> Bool {
        indent + nodes.flat.count <= limit && !nodes.contains(where: Self.holdsSeveralStatements)
    }

    static func holdsSeveralStatements(_ node: LayoutNode) -> Bool {
        guard case let .group(open, children, _) = node else { return false }
        if open == "{", ClosureHead.split(children).body.split(on: ";").filter({ !$0.isEmpty }).count > 1 {
            return true
        }
        return children.contains(where: holdsSeveralStatements)
    }

    // MARK: - Chains

    /// `head` then each call on its own line, led by its `.` — or `nil` when there are fewer than
    /// two calls in the chain.
    ///
    /// A head that ends by *invoking* what a bracket holds — `({ … })()`, a held receiver built in
    /// place — is a call too, as SwiftLint counts it; it stays on the head's line, since a line
    /// break before `(` would start a new statement.
    func chainLines(_ nodes: [LayoutNode], indent: Int) -> [String]? {
        let segments = ChainSegments(nodes)
        let invoked = Self.endsByInvoking(segments.head) ? 1 : 0
        guard segments.calls.count + invoked >= 2, !segments.calls.isEmpty,
              !segments.head.flat.allSatisfy({ $0 == " " }) else { return nil }
        let head = lines(for: segments.head.trimmed, indent: indent)
        let callIndent = head.count == 1 ? indent + indentWidth : indent
        return head + segments.calls.flatMap { lines(for: $0.trimmed, indent: callIndent) }
    }

    /// Whether `nodes` end `(…)(…)` or `{…}(…)`: an argument list applied to a bracket's result.
    static func endsByInvoking(_ nodes: [LayoutNode]) -> Bool {
        let trimmed = nodes.trimmed
        guard trimmed.count >= 2, case .group("(", _, _) = trimmed[trimmed.count - 1],
              case .group = trimmed[trimmed.count - 2] else { return false }
        return true
    }

    // MARK: - Groups

    func groupLines(_ nodes: [LayoutNode], indent: Int) -> [String]? {
        let candidates = nodes.indices.filter { Self.isBreakable(nodes[$0]) }
        guard let first = candidates.first else { return nil }
        let fitting = candidates.filter { openingLine(nodes, at: $0).count + indent <= limit }
        var chosen = fitting.first ?? first
        for index in fitting where nodes[index].flat.count > nodes[chosen].flat.count {
            chosen = index
        }
        return broken(nodes, at: chosen, indent: indent)
    }

    static func isBreakable(_ node: LayoutNode) -> Bool {
        guard case let .group(_, children, _) = node else { return false }
        return !children.trimmed.isEmpty
    }

    /// The line a break at `index` starts with: everything before the group, and its opener.
    func openingLine(_ nodes: [LayoutNode], at index: Int) -> String {
        guard case let .group(open, children, _) = nodes[index] else { return "" }
        let prefix = Array(nodes[..<index])
        guard open == "{" else { return prefix.flat + String(open) }
        let head = BraceBody(prefix: prefix, children: children).head
        return prefix.flat + "{" + (head.isEmpty ? "" : " \(head) in")
    }

    func broken(_ nodes: [LayoutNode], at index: Int, indent: Int) -> [String] {
        guard case let .group(open, children, close) = nodes[index] else { return [] }
        let pad = String(repeating: " ", count: indent)
        let prefix = Array(nodes[..<index])
        let closing = [LayoutNode.text(String(close))] + nodes[(index + 1)...]
        let inner = indent + indentWidth
        let body: [String]
        if open == "{" {
            let brace = BraceBody(prefix: prefix, children: children)
            let opening = pad + prefix.flat + "{" + (brace.head.isEmpty ? "" : " \(brace.head) in")
            body = [opening] + brace.statements.flatMap { lines(for: $0, indent: inner) }
        } else {
            let elements = children.split(on: ",").filter { !$0.isEmpty }
            body = [pad + prefix.flat + String(open)] + listLines(elements, filling: open == "[", indent: inner)
        }
        return body + lines(for: closing, indent: indent)
    }

    /// The elements of a broken list. As many to a line as fit when no element holds a closure or
    /// a block — a generator's `zip(…)` arguments, a memberwise initializer's labels, an array of
    /// literals — and one per line otherwise, so a call taking closures reads one argument at a
    /// time. An element too long for a line of its own is broken onto lines of its own.
    ///
    /// Packing is what keeps a generated test inside `function_body_length`: a memberwise
    /// generator one element per line runs to 76 lines for a five-field type of five-field
    /// arrays, against the rule's 50.
    func listLines(_ elements: [[LayoutNode]], filling: Bool, indent: Int) -> [String] {
        let pieces = elements.enumerated().map { offset, element in
            offset < elements.count - 1 ? element + [.text(",")] : element
        }
        guard filling || !pieces.contains(where: { $0.contains(where: Self.holdsBrace) }) else {
            return pieces.flatMap { lines(for: $0, indent: indent) }
        }
        let pad = String(repeating: " ", count: indent)
        var result: [String] = []
        var current = ""
        for piece in pieces {
            guard fits(piece, indent: indent) else {
                if !current.isEmpty { result.append(pad + current) }
                current = ""
                result += lines(for: piece, indent: indent)
                continue
            }
            let flat = piece.flat
            if current.isEmpty {
                current = flat
            } else if indent + current.count + 1 + flat.count <= limit {
                current += " " + flat
            } else {
                result.append(pad + current)
                current = flat
            }
        }
        return current.isEmpty ? result : result + [pad + current]
    }

    static func holdsBrace(_ node: LayoutNode) -> Bool {
        guard case let .group(open, children, _) = node else { return false }
        return open == "{" || children.contains(where: holdsBrace)
    }
}

/// A brace group's body ready to be broken: the closure's parameters, if it is a closure and has
/// them — named for it when it used `$0`, which `shorthand_argument` refuses more than a few
/// lines below the brace — and its statements.
struct BraceBody {

    let head: String
    let statements: [[LayoutNode]]

    init(prefix: [LayoutNode], children: [LayoutNode]) {
        let isClosure = Self.isClosure(prefix: prefix)
        let split = isClosure ? ClosureHead.split(children) : (head: "", body: children)
        if isClosure, split.head.isEmpty, let named = ShorthandNames.naming(children) {
            head = named.head
            statements = named.body.split(on: ";").filter { !$0.isEmpty }
        } else {
            head = split.head
            statements = split.body.split(on: ";").filter { !$0.isEmpty }
        }
    }

    /// Whether the brace after `prefix` opens a closure rather than a statement's block — read
    /// from the words before it, which for a block always include its keyword.
    static func isClosure(prefix: [LayoutNode]) -> Bool {
        let keywords: Set<Substring> = [
            "if", "guard", "else", "for", "while", "switch", "do", "catch", "repeat", "defer", "func",
            "init", "deinit", "get", "set", "willSet", "didSet", "struct", "class", "enum", "extension",
            "protocol", "actor"
        ]
        let words = prefix.compactMap { node -> String? in
            guard case .text(let text) = node else { return nil }
            return text
        }
        .joined(separator: " ")
        .split { !($0.isLetter || $0.isNumber || $0 == "_") }
        return !words.contains(where: keywords.contains)
    }
}
