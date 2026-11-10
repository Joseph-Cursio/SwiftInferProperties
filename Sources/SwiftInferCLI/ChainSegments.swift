import Foundation

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
