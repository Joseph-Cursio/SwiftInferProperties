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
