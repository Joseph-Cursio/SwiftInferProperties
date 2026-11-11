import SwiftSyntax

/// Where a body decorates a name with a counter (`uniquifier-law-census-scope.md` §1.2, *SUFFIX*).
struct CounterDecoration {
    /// The interpolation or call that decorates.
    let node: Syntax
    /// The counter: a counted chain, `<chain>.count`, or `<table>[]` for a counter table's entry.
    let counter: String
    /// The literal text written just before the counter: `"_"` in `"\(base)_\(n)"`.
    let prefix: String
}

extension UniquifierBody {
    /// Every counter decoration in the body.
    func decorations(_ facts: UniquifierCounters) -> [CounterDecoration] {
        var found: [CounterDecoration] = []
        for node in nodes {
            if let literal = node.as(StringLiteralExprSyntax.self) {
                found += Self.interpolatedCounters(in: literal, facts)
            } else if let counter = Self.stringifiedCounter(node, facts) {
                found.append(CounterDecoration(node: node, counter: counter, prefix: ""))
            }
        }
        return found
    }

    /// `"\(name)\(index)"`, `"\(n + 1)"`, `"\(names.count)"`, `"\(counts[b]!)"`.
    private static func interpolatedCounters(
        in literal: StringLiteralExprSyntax,
        _ facts: UniquifierCounters
    ) -> [CounterDecoration] {
        var found: [CounterDecoration] = []
        var prefix = ""
        for segment in literal.segments {
            switch segment {
            case .stringSegment(let text):
                prefix = String(text.content.text.reversed().prefix { !$0.isLetter && !$0.isNumber }.reversed())

            case .expressionSegment(let interpolation):
                if let expression = interpolation.expressions.first?.expression,
                   let counter = counterName(expression, facts) {
                    found.append(CounterDecoration(node: Syntax(interpolation), counter: counter, prefix: prefix))
                }
                prefix = ""
            }
        }
        return found
    }

    /// The counter an interpolated expression names, `± <digits>` removed.
    private static func counterName(_ expression: ExprSyntax, _ facts: UniquifierCounters) -> String? {
        var expression = expression
        if let sequence = expression.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            guard elements.count == 3, isOperator(elements[1], ["+", "-"]),
                  elements[2].is(IntegerLiteralExprSyntax.self) else {
                return nil
            }
            expression = elements[0]
        }
        let unwrapped = expression.as(ForceUnwrapExprSyntax.self)?.expression ?? expression
        if let access = unwrapped.as(SubscriptCallExprSyntax.self),
           let table = chain(access.calledExpression).map(base(of:)), facts.tables.contains(table) {
            return table + "[]"
        }
        guard let name = chain(expression) else { return nil }
        if facts.counted.contains(name) || name.hasSuffix(".count") {
            return name
        }
        return nil
    }

    /// `String(n)`, `String(describing: n)` or `n.description` for a counter `n`.
    private static func stringifiedCounter(_ node: Syntax, _ facts: UniquifierCounters) -> String? {
        if let call = node.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "String",
           call.arguments.count == 1, let argument = call.arguments.first,
           argument.label == nil || argument.label?.text == "describing",
           let name = chain(argument.expression), facts.counted.contains(name) {
            return name
        }
        if let member = node.as(MemberAccessExprSyntax.self), member.declName.baseName.text == "description",
           let base = member.base, let name = chain(base), facts.counted.contains(name) {
            return name
        }
        return nil
    }

    /// The spans a test decides: an `if`'s or `while`'s body when its condition holds a test, the `else`
    /// block straight after such an `if`, such a `guard`'s `else`, a `repeat` body whose `while` holds
    /// one, and a ternary's branches after a test.
    func decidedSpans(_ tests: [MembershipTest]) -> [Syntax] {
        func holdsTest(_ region: some SyntaxProtocol) -> Bool {
            tests.contains { Self.isInside($0.node, region) }
        }
        var spans: [Syntax] = []
        for node in nodes {
            if let branch = node.as(IfExprSyntax.self), holdsTest(branch.conditions) {
                spans.append(Syntax(branch.body))
                if case .codeBlock(let block)? = branch.elseBody { spans.append(Syntax(block)) }
            } else if let loop = node.as(WhileStmtSyntax.self), holdsTest(loop.conditions) {
                spans.append(Syntax(loop.body))
            } else if let guarded = node.as(GuardStmtSyntax.self), holdsTest(guarded.conditions) {
                spans.append(Syntax(guarded.body))
            } else if let loop = node.as(RepeatStmtSyntax.self), holdsTest(loop.condition) {
                spans.append(Syntax(loop.body))
            } else if let sequence = node.as(SequenceExprSyntax.self) {
                spans += Self.ternaryBranches(sequence, deciding: holdsTest)
            }
        }
        return spans
    }

    private static func ternaryBranches(
        _ sequence: SequenceExprSyntax,
        deciding holdsTest: (ExprSyntax) -> Bool
    ) -> [Syntax] {
        let elements = Array(sequence.elements)
        guard let index = elements.firstIndex(where: { $0.is(UnresolvedTernaryExprSyntax.self) }),
              elements[..<index].contains(where: holdsTest),
              let ternary = elements[index].as(UnresolvedTernaryExprSyntax.self) else {
            return []
        }
        return [Syntax(ternary.thenExpression)] + elements[(index + 1)...].map(Syntax.init)
    }

    /// RETEST: a `while`, or a `repeat`'s trailing one, whose condition tests an argument the loop body
    /// reassigns. Each found loop's tested chain, with the loop body.
    func retests(_ tests: [MembershipTest]) -> [(chain: String, body: CodeBlockSyntax)] {
        var found: [(chain: String, body: CodeBlockSyntax)] = []
        for node in nodes {
            let loop: (condition: Syntax, body: CodeBlockSyntax)?
            if let whileLoop = node.as(WhileStmtSyntax.self) {
                loop = (Syntax(whileLoop.conditions), whileLoop.body)
            } else if let repeatLoop = node.as(RepeatStmtSyntax.self) {
                loop = (Syntax(repeatLoop.condition), repeatLoop.body)
            } else {
                loop = nil
            }
            guard let loop else { continue }
            for test in tests where Self.isInside(test.node, loop.condition)
                && Self.freeNames(in: test.argument).contains(where: { reassigns($0, in: loop.body) }) {
                found.append((test.chain, loop.body))
            }
        }
        return found
    }

    /// `name = …`, `name += …`, `name &+= …` or `name.append(…)` inside `region`.
    func reassigns(_ name: String, in region: some SyntaxProtocol) -> Bool {
        nodes.contains { node in
            guard Self.isInside(node, region) else { return false }
            if let elements = node.as(SequenceExprSyntax.self).map({ Array($0.elements) }), elements.count >= 3,
               Self.chain(elements[0]) == name,
               elements[1].is(AssignmentExprSyntax.self) || Self.isOperator(elements[1], ["+=", "&+="]) {
                return true
            }
            if let call = node.as(FunctionCallExprSyntax.self),
               case let ("append", chain)? = Self.calledMember(call), chain == name {
                return true
            }
            return false
        }
    }
}
