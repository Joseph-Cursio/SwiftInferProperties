import SwiftSyntax

extension UniquifierBody {
    /// TIED, #669's "on a hit decorates the candidate" (`uniquifier-law-census-scope.md` §1.2). A decoration
    /// is tied to a test when any of these holds:
    ///
    /// - its counter was read from a tested base, or is a tested counter table's entry: a per-key counter;
    /// - it sits inside a test's argument, or inside what is written to a tested base;
    /// - the variable its statement assigns is a test's argument, or is written to a tested base;
    /// - it sits in a span a test decides, and it is returned.
    func isTied(
        _ decoration: CounterDecoration,
        tests: [MembershipTest],
        spans: [Syntax],
        facts: UniquifierCounters
    ) -> Bool {
        let testedBases = Set(tests.map(\.base))
        let counterBase = decoration.counter.hasSuffix("[]") ? String(decoration.counter.dropLast(2)) : nil
        if let source = facts.sources[decoration.counter], testedBases.contains(source) { return true }
        if let counterBase, testedBases.contains(counterBase) { return true }
        let writes = writtenValues(to: testedBases)
        let regions = tests.map(\.argument) + writes
        if regions.contains(where: { Self.isInside(decoration.node, $0) }) { return true }
        if let variable = assignedVariable(of: decoration.node) {
            if tests.contains(where: { Self.freeNames(in: $0.argument).contains(variable) }) { return true }
            if writes.contains(where: { Self.freeNames(in: $0).contains(variable) }) { return true }
        }
        return spans.contains { Self.isInside(decoration.node, $0) } && isReturned(decoration.node)
    }

    /// Whether `node` is returned: its statement is a `return`, or builds a variable a `return` names.
    func isReturned(_ node: Syntax) -> Bool {
        if Self.statement(of: node)?.item.is(ReturnStmtSyntax.self) == true { return true }
        guard let variable = assignedVariable(of: node) else { return false }
        return nodes.contains { candidate in
            guard let returned = candidate.as(ReturnStmtSyntax.self)?.expression else { return false }
            return Self.freeNames(in: returned).contains(variable)
        }
    }

    /// The variable the statement holding `node` declares or assigns: `let name = …`, `name += …`.
    func assignedVariable(of node: Syntax) -> String? {
        guard let item = Self.statement(of: node)?.item else { return nil }
        if let declaration = item.as(VariableDeclSyntax.self), declaration.bindings.count == 1,
           let name = declaration.bindings.first?.pattern.as(IdentifierPatternSyntax.self) {
            return name.identifier.text
        }
        guard let elements = item.as(SequenceExprSyntax.self).map({ Array($0.elements) }), elements.count >= 3,
              elements[1].is(AssignmentExprSyntax.self) || Self.isOperator(elements[1], ["+="]),
              let target = Self.chain(elements[0]), !target.contains(".") else {
            return nil
        }
        return target
    }

    /// What the body writes to `bases`: a write call's arguments, and the right-hand side of a subscript or
    /// whole assignment.
    func writtenValues(to bases: Set<String>) -> [Syntax] {
        var values: [Syntax] = []
        for node in nodes {
            if let call = node.as(FunctionCallExprSyntax.self), case let (name, chain)? = Self.calledMember(call),
               Self.writeCalls.contains(name), bases.contains(Self.base(of: chain)) {
                values.append(Syntax(call.arguments))
            } else if let elements = node.as(SequenceExprSyntax.self).map({ Array($0.elements) }),
                      let target = Self.assignmentTarget(elements), bases.contains(Self.base(of: target)) {
                values += elements.dropFirst(2).map(Syntax.init)
            }
        }
        return values
    }

    /// The calls that write a collection (§1.2, *WRITE*).
    static let writeCalls: Set<String> = [
        "append", "insert", "formUnion", "updateValue", "merge", "add", "unionInPlace",
    ]

    /// The chain an assignment writes, through a subscript or whole: `t[k] = v` and `t = v` are `t`.
    static func assignmentTarget(_ elements: [ExprSyntax]) -> String? {
        guard elements.count >= 3,
              elements[1].is(AssignmentExprSyntax.self) || isOperator(elements[1], ["+=", "&+="]) else {
            return nil
        }
        if let access = elements[0].as(SubscriptCallExprSyntax.self) {
            return chain(access.calledExpression)
        }
        return chain(elements[0])
    }
}
