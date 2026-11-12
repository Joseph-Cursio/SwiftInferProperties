import SwiftSyntax

/// What counts in a body (`uniquifier-law-census-scope.md` §1.2, *Counters*).
struct UniquifierCounters {
    /// Every name or chain that counts.
    var counted: Set<String> = []
    /// For a counter read from a subscript, the base of the collection it was read from.
    var sources: [String: String] = [:]
    /// The incremented chains whose base is stored.
    var storedIncrements: Set<String> = []
    /// Bases of subscripts incremented in place: `t[k, default: 0] += 1`.
    var tables: Set<String> = []
    /// A local copied from an incremented chain (`let id = next`), and that chain.
    var aliases: [String: String] = [:]
}

extension UniquifierBody {
    /// The body's counters.
    func counters() -> UniquifierCounters {
        var facts = UniquifierCounters()
        var incremented: Set<String> = []
        var loops: Set<String> = []
        for node in nodes {
            if let sequence = node.as(SequenceExprSyntax.self) {
                let elements = Array(sequence.elements)
                if let chain = Self.incrementedChain(elements) { incremented.insert(chain) }
                if let table = Self.incrementedTable(elements) { facts.tables.insert(table) }
            } else if let loop = node.as(ForStmtSyntax.self), Self.isRangeLoop(loop),
                      let name = loop.pattern.as(IdentifierPatternSyntax.self) {
                loops.insert(name.identifier.text)
            }
        }
        for (name, value) in bindings() {
            if let source = Self.boundCounterSource(value) {
                facts.sources[name] = source
            } else if let chain = Self.chain(value), incremented.contains(chain) {
                facts.aliases[name] = chain
            } else if let table = Self.readTable(value),
                      facts.tables.contains(table) || writesBack(table: table, from: name) {
                facts.sources[name] = table
            }
        }
        facts.storedIncrements = incremented.filter { isStored(Self.base(of: $0)) }
        facts.counted = incremented.union(facts.sources.keys).union(loops).union(facts.aliases.keys)
        return facts
    }

    /// `(name, value)` for every `let`/`var` binding and every optional-binding condition.
    func bindings() -> [(String, ExprSyntax)] {
        nodes.compactMap { node in
            if let binding = node.as(PatternBindingSyntax.self),
               let name = binding.pattern.as(IdentifierPatternSyntax.self),
               let value = binding.initializer?.value {
                return (name.identifier.text, value)
            }
            if let condition = node.as(OptionalBindingConditionSyntax.self),
               let name = condition.pattern.as(IdentifierPatternSyntax.self),
               let value = condition.initializer?.value {
                return (name.identifier.text, value)
            }
            return nil
        }
    }

    /// `n += 1`, `n &+= 1`, `n = n + 1`: the incremented chain.
    static func incrementedChain(_ elements: [ExprSyntax]) -> String? {
        if elements.count == 3, isOperator(elements[1], ["+=", "&+="]), isLiteral(elements[2], "1") {
            return chain(elements[0])
        }
        if elements.count == 5, elements[1].is(AssignmentExprSyntax.self),
           let target = chain(elements[0]), chain(elements[2]) == target,
           isOperator(elements[3], ["+", "&+"]), isLiteral(elements[4], "1") {
            return target
        }
        return nil
    }

    /// `t[k, default: 0] += 1` or `t[k] = (t[k] ?? 0) + 1`: the table's base.
    private static func incrementedTable(_ elements: [ExprSyntax]) -> String? {
        guard let access = elements.first?.as(SubscriptCallExprSyntax.self),
              let table = chain(access.calledExpression).map(base(of:)) else {
            return nil
        }
        if elements.count == 3, isOperator(elements[1], ["+=", "&+="]), isLiteral(elements[2], "1") {
            return table
        }
        if elements.count >= 5, elements[1].is(AssignmentExprSyntax.self),
           let last = elements.last, isLiteral(last, "1"),
           isOperator(elements[elements.count - 2], ["+"]),
           elements.dropFirst(2).contains(where: { $0.trimmedDescription.contains(table + "[") }) {
            return table
        }
        return nil
    }

    /// `t[k, default: 0]`, `t[k] ?? 0`, `(t[k] ?? 0) + 1`: the base a counter was read from.
    private static func boundCounterSource(_ value: ExprSyntax) -> String? {
        var expression = value
        if let sequence = expression.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            guard elements.count == 3, isOperator(elements[1], ["+", "-"]),
                  elements[2].is(IntegerLiteralExprSyntax.self) else {
                return coalescedTable(elements)
            }
            expression = elements[0]
        }
        if let tuple = expression.as(TupleExprSyntax.self), tuple.elements.count == 1,
           let inner = tuple.elements.first?.expression {
            expression = inner
        }
        if let sequence = expression.as(SequenceExprSyntax.self) {
            return coalescedTable(Array(sequence.elements))
        }
        guard let access = expression.as(SubscriptCallExprSyntax.self),
              access.arguments.contains(where: {
                  $0.label?.text == "default" && $0.expression.is(IntegerLiteralExprSyntax.self)
              }) else {
            return nil
        }
        return chain(access.calledExpression).map(base(of:))
    }

    /// `t[k] ?? 0`: `t`.
    private static func coalescedTable(_ elements: [ExprSyntax]) -> String? {
        guard elements.count == 3, isOperator(elements[1], ["??"]),
              elements[2].is(IntegerLiteralExprSyntax.self),
              let access = elements[0].as(SubscriptCallExprSyntax.self) else {
            return nil
        }
        return chain(access.calledExpression).map(base(of:))
    }

    /// `t[k]` or `t[k]!` without `default:`: `t`.
    private static func readTable(_ value: ExprSyntax) -> String? {
        let expression = value.as(ForceUnwrapExprSyntax.self)?.expression ?? value
        guard let access = expression.as(SubscriptCallExprSyntax.self),
              !access.arguments.contains(where: { $0.label?.text == "default" }) else {
            return nil
        }
        return chain(access.calledExpression).map(base(of:))
    }

    /// The body writes `table[…] = name ± <digits>`.
    private func writesBack(table: String, from name: String) -> Bool {
        nodes.contains { node in
            guard let elements = node.as(SequenceExprSyntax.self).map({ Array($0.elements) }),
                  elements.count == 5, elements[1].is(AssignmentExprSyntax.self),
                  let access = elements[0].as(SubscriptCallExprSyntax.self),
                  Self.chain(access.calledExpression).map(Self.base(of:)) == table else {
                return false
            }
            return Self.chain(elements[2]) == name && Self.isOperator(elements[3], ["+", "-"])
                && elements[4].is(IntegerLiteralExprSyntax.self)
        }
    }

    private static func isRangeLoop(_ loop: ForStmtSyntax) -> Bool {
        guard let sequence = loop.sequence.as(SequenceExprSyntax.self) else { return false }
        return sequence.elements.contains { isOperator($0, ["...", "..<"]) }
    }

    static func isOperator(_ expression: ExprSyntax, _ spellings: Set<String>) -> Bool {
        guard let operation = expression.as(BinaryOperatorExprSyntax.self) else { return false }
        return spellings.contains(operation.operator.text)
    }

    static func isLiteral(_ expression: ExprSyntax, _ digits: String) -> Bool {
        expression.as(IntegerLiteralExprSyntax.self)?.literal.text == digits
    }
}
