import SwiftSyntax

extension UniquifierBody {
    /// The calls that remove from a collection, so a pool can hand a released name out again.
    static let removeCalls: Set<String> = [
        "remove", "removeValue", "removeAll", "removeFirst", "removeLast", "removeSubrange",
        "subtract", "popFirst", "popLast",
    ]

    /// The first node that writes stored `base`: a write call on it or a chain below it, or a subscript or
    /// whole assignment to it.
    func firstWrite(of base: String) -> Syntax? {
        nodes.first { node in
            if let call = node.as(FunctionCallExprSyntax.self), case let (name, chain)? = Self.calledMember(call) {
                return Self.writeCalls.contains(name) && Self.base(of: chain) == base
            }
            if let elements = node.as(SequenceExprSyntax.self).map({ Array($0.elements) }),
               let target = Self.assignmentTarget(elements) {
                return Self.base(of: target) == base
            }
            return false
        }
    }

    /// The stored state the body writes and removes from.
    func stateWrites() -> StateWrites {
        var written: Set<String> = []
        var removed: Set<String> = []
        for node in nodes {
            if let call = node.as(FunctionCallExprSyntax.self), case let (name, chain)? = Self.calledMember(call) {
                let base = Self.base(of: chain)
                guard isStored(base) else { continue }
                if Self.writeCalls.contains(name) { written.insert(base) }
                if Self.removeCalls.contains(name) { removed.insert(base) }
            } else if let elements = node.as(SequenceExprSyntax.self).map({ Array($0.elements) }),
                      let target = Self.assignmentTarget(elements), isStored(Self.base(of: target)) {
                let base = Self.base(of: target)
                if elements.count == 3, elements[0].is(SubscriptCallExprSyntax.self),
                   elements[2].is(NilLiteralExprSyntax.self) {
                    removed.insert(base)
                } else {
                    written.insert(base)
                }
            }
        }
        return StateWrites(written: written, removed: removed)
    }
}
