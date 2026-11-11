import SwiftSyntax

extension UniquifierBody {
    /// Every membership test in the body, in source order.
    func membershipTests() -> [MembershipTest] {
        var found: [MembershipTest] = []
        for node in nodes {
            if let test = Self.callTest(node) ?? Self.subscriptTest(node) {
                found.append(test)
            }
        }
        return found
    }

    /// `contains(…)`, `index(forKey:)` and `insert(…).inserted`.
    private static func callTest(_ node: Syntax) -> MembershipTest? {
        if let member = node.as(MemberAccessExprSyntax.self), member.declName.baseName.text == "inserted",
           let call = member.base?.as(FunctionCallExprSyntax.self),
           case let (name, chain)? = calledMember(call), name == "insert" {
            return MembershipTest(kind: .inserted, chain: chain, node: node, argument: Syntax(call.arguments))
        }
        guard let call = node.as(FunctionCallExprSyntax.self), case let (name, chain)? = calledMember(call) else {
            return nil
        }
        if name == "contains" {
            return MembershipTest(kind: .contains, chain: chain, node: node, argument: Syntax(call.arguments))
        }
        if name == "index", call.arguments.first?.label?.text == "forKey" {
            return MembershipTest(kind: .indexForKey, chain: chain, node: node, argument: Syntax(call.arguments))
        }
        return nil
    }

    /// `t[k, default: …]`, `t[k] == nil`, `t[k] ?? …` and `if let v = t[k]`.
    private static func subscriptTest(_ node: Syntax) -> MembershipTest? {
        guard let access = node.as(SubscriptCallExprSyntax.self),
              let chain = chain(access.calledExpression) else {
            return nil
        }
        let argument = Syntax(access.arguments)
        if access.arguments.contains(where: { $0.label?.text == "default" }) {
            return MembershipTest(kind: .defaultSubscript, chain: chain, node: node, argument: argument)
        }
        if let kind = operatorTestKind(following: access) {
            return MembershipTest(kind: kind, chain: chain, node: node, argument: argument)
        }
        if access.parent?.as(InitializerClauseSyntax.self)?.parent?.is(OptionalBindingConditionSyntax.self) == true {
            return MembershipTest(kind: .binding, chain: chain, node: node, argument: argument)
        }
        return nil
    }

    /// `(name, chain)` for a call on a member of a plain chain: `self.names.contains(x)` → `("contains", "names")`.
    static func calledMember(_ call: FunctionCallExprSyntax) -> (String, String)? {
        guard let callee = call.calledExpression.as(MemberAccessExprSyntax.self),
              let base = callee.base, let chain = chain(base) else {
            return nil
        }
        return (callee.declName.baseName.text, chain)
    }

    /// The operator after a subscript in an unfolded sequence: `== nil` / `!= nil`, or `??`.
    private static func operatorTestKind(following access: SubscriptCallExprSyntax) -> MembershipTest.Kind? {
        guard let elements = access.parent?.as(ExprListSyntax.self),
              let index = elements.firstIndex(where: { $0.id == access.id }) else {
            return nil
        }
        let rest = Array(elements[index...].dropFirst())
        guard let operation = rest.first?.as(BinaryOperatorExprSyntax.self)?.operator.text else { return nil }
        if operation == "??" { return .coalesce }
        if ["==", "!="].contains(operation), rest.count > 1, rest[1].is(NilLiteralExprSyntax.self) {
            return .nilCompare
        }
        return nil
    }
}
