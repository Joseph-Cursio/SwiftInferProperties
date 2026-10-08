import SwiftSyntax

/// One key of a comparator's tie-break chain: the member both operands are compared on, and which
/// way it sorts.
public struct SortKey: Sendable, Equatable {
    /// The member path compared on both operands — `fileCount`, or `location.line`.
    public let path: String
    /// `true` when the smaller value sorts first.
    public let ascending: Bool

    public init(path: String, ascending: Bool) {
        self.path = path
        self.ascending = ascending
    }
}

/// The ordering a function's result is sorted by, read from the comparator it sorts with
/// (SwiftInferProperties#647).
///
/// ```swift
/// .sorted { lhs, rhs in
///     if lhs.fileCount != rhs.fileCount { return lhs.fileCount > rhs.fileCount }
///     if lhs.findingCount != rhs.findingCount { return lhs.findingCount > rhs.findingCount }
///     return lhs.ruleID < rhs.ruleID
/// }
/// ```
///
/// states that the result is ordered by `(fileCount ↓, findingCount ↓, ruleID ↑)`. The law is read
/// from the comparator, as `GuardDomain`'s is read from the guard, so it holds of the code it was
/// read from by construction — except when the comparator is not a strict weak ordering, which is
/// the one way `sorted(by:)` can return an array its own comparator calls unsorted.
public struct SortedOutput: Sendable, Equatable {
    /// The member of the returned value that holds the sorted array — `ruleImpacts` in
    /// `Self(…, ruleImpacts: impacts)` — or `nil` when the function returns the array itself.
    public let member: String?
    /// The comparator's keys in priority order; the last is the final tie-break.
    public let keys: [SortKey]

    public init(member: String?, keys: [SortKey]) {
        self.member = member
        self.keys = keys
    }
}

/// Reads a `SortedOutput` from a function body, or `nil` when the body does not return a sorted
/// array in a shape whose ordering can be restated.
///
/// Two shapes are read, both measured on the survivors that motivated the template:
///
/// - **returned directly**: `return results.filter { … }.sorted { … }`;
/// - **returned as a member**: `let impacts = ….sorted { … }` and then `return Self(…, ruleImpacts:
///   impacts)`. The member is the argument label, which is the property name for a memberwise
///   initializer and for the explicit ones that mirror it.
///
/// The comparator has to be a chain the reader can restate exactly: zero or more
/// `if a.k != b.k { return a.k OP b.k }`, then `return a.k OP b.k`, with `OP` one of `<` and `>`.
/// Anything else — a call in the comparison, a computed key, `sorted()` with no closure — is
/// declined rather than approximated.
public enum SortedOutputReader {

    public static func read(_ function: FunctionDeclSyntax) -> SortedOutput? {
        guard let statements = function.body?.statements,
              let last = statements.last?.item,
              let returned = returnedExpression(last, isOnlyStatement: statements.count == 1) else {
            return nil
        }
        if let keys = sortKeys(ofSortedCall: returned) {
            return SortedOutput(member: nil, keys: keys)
        }
        guard let construction = returned.as(FunctionCallExprSyntax.self) else { return nil }
        let locals = sortedLocals(in: statements)
        var found: [SortedOutput] = []
        for argument in construction.arguments {
            guard let label = argument.label?.text else { continue }
            if let keys = sortKeys(ofSortedCall: argument.expression) {
                found.append(SortedOutput(member: label, keys: keys))
            } else if let name = argument.expression.as(DeclReferenceExprSyntax.self)?.baseName.text,
                      let keys = locals[name] {
                found.append(SortedOutput(member: label, keys: keys))
            }
        }
        // Two sorted members would be two laws, and a suggestion carries one.
        return found.count == 1 ? found.first : nil
    }

    private static func returnedExpression(_ item: CodeBlockItemSyntax.Item, isOnlyStatement: Bool) -> ExprSyntax? {
        if let returnStmt = item.as(ReturnStmtSyntax.self) { return returnStmt.expression }
        guard isOnlyStatement else { return nil }
        return item.as(ExpressionStmtSyntax.self)?.expression ?? item.as(ExprSyntax.self)
    }

    /// `let name = ….sorted { … }` bindings in the body's top-level statements.
    private static func sortedLocals(in statements: CodeBlockItemListSyntax) -> [String: [SortKey]] {
        var locals: [String: [SortKey]] = [:]
        for statement in statements {
            guard let declaration = statement.item.as(VariableDeclSyntax.self),
                  declaration.bindingSpecifier.tokenKind == .keyword(.let),
                  declaration.bindings.count == 1,
                  let binding = declaration.bindings.first,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let value = binding.initializer?.value,
                  let keys = sortKeys(ofSortedCall: value) else {
                continue
            }
            locals[name] = keys
        }
        return locals
    }

    /// The keys of `x.sorted { … }` or `x.sorted(by: { … })`.
    static func sortKeys(ofSortedCall expression: ExprSyntax) -> [SortKey]? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let callee = call.calledExpression.as(MemberAccessExprSyntax.self),
              callee.declName.baseName.text == "sorted",
              call.additionalTrailingClosures.isEmpty else {
            return nil
        }
        if let trailing = call.trailingClosure, call.arguments.isEmpty {
            return keys(of: trailing)
        }
        guard call.trailingClosure == nil,
              call.arguments.count == 1,
              let argument = call.arguments.first,
              argument.label?.text == "by",
              let closure = argument.expression.as(ClosureExprSyntax.self) else {
            return nil
        }
        return keys(of: closure)
    }

    private static func keys(of closure: ClosureExprSyntax) -> [SortKey]? {
        guard let operands = operandNames(of: closure) else { return nil }
        let items = Array(closure.statements.map(\.item))
        guard let lastItem = items.last else { return nil }

        var keys: [SortKey] = []
        for item in items.dropLast() {
            guard let key = tieBreak(item, operands: operands) else { return nil }
            keys.append(key)
        }
        // The last statement returns the final key's comparison — bare when it is the only one.
        guard let finalComparison = returnedExpression(lastItem, isOnlyStatement: items.count == 1),
              let key = orderingKey(finalComparison, operands: operands) else {
            return nil
        }
        keys.append(key)
        // A key compared twice is not a chain this reader restates faithfully.
        guard Set(keys.map(\.path)).count == keys.count else { return nil }
        return keys
    }

    /// `(lhs, rhs)` from `{ lhs, rhs in … }` or `{ (lhs, rhs) in … }`; `($0, $1)` when the closure
    /// names neither.
    private static func operandNames(of closure: ClosureExprSyntax) -> (String, String)? {
        guard let signature = closure.signature else { return ("$0", "$1") }
        switch signature.parameterClause {
        case .simpleInput(let list):
            let names = list.map(\.name.text)
            return names.count == 2 ? (names[0], names[1]) : nil

        case .parameterClause(let clause):
            let names = clause.parameters.map { ($0.secondName ?? $0.firstName).text }
            return names.count == 2 ? (names[0], names[1]) : nil

        case nil:
            return ("$0", "$1")
        }
    }

    /// `if a.k != b.k { return a.k OP b.k }`, as the key it breaks ties on.
    private static func tieBreak(_ item: CodeBlockItemSyntax.Item, operands: (String, String)) -> SortKey? {
        guard let ifExpr = item.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self),
              ifExpr.elseBody == nil,
              ifExpr.conditions.count == 1,
              let condition = ifExpr.conditions.first,
              case .expression(let test) = condition.condition,
              let inequality = comparison(test), inequality.operation == "!=",
              ifExpr.body.statements.count == 1,
              let returned = ifExpr.body.statements.first?.item.as(ReturnStmtSyntax.self)?.expression,
              let key = orderingKey(returned, operands: operands),
              let testedPath = path(comparing: inequality, operands: operands, eitherOrder: true),
              testedPath == key.path else {
            return nil
        }
        return key
    }

    /// `a.k < b.k` (ascending) or `a.k > b.k` (descending); swapped operands invert the direction.
    private static func orderingKey(_ expression: ExprSyntax, operands: (String, String)) -> SortKey? {
        guard let parts = comparison(expression), parts.operation == "<" || parts.operation == ">" else {
            return nil
        }
        let ascendingIfInOrder = parts.operation == "<"
        if let path = path(comparing: parts, operands: operands, eitherOrder: false) {
            return SortKey(path: path, ascending: ascendingIfInOrder)
        }
        if let path = path(comparing: parts, operands: (operands.1, operands.0), eitherOrder: false) {
            return SortKey(path: path, ascending: !ascendingIfInOrder)
        }
        return nil
    }

    /// The member path when `parts` compares `first.path` with `second.path`.
    private static func path(
        comparing parts: Comparison,
        operands: (String, String),
        eitherOrder: Bool
    ) -> String? {
        if let path = memberPath(parts.lhs, of: operands.0), memberPath(parts.rhs, of: operands.1) == path {
            return path
        }
        guard eitherOrder else { return nil }
        if let path = memberPath(parts.lhs, of: operands.1), memberPath(parts.rhs, of: operands.0) == path {
            return path
        }
        return nil
    }

    /// `fileCount` from `lhs.fileCount`, when the rest is a plain member chain — no calls, no
    /// subscripts, nothing a test would have to evaluate differently from the comparator.
    private static func memberPath(_ text: String, of operand: String) -> String? {
        let prefix = operand + "."
        guard text.hasPrefix(prefix) else { return nil }
        let path = String(text.dropFirst(prefix.count))
        let components = path.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.allSatisfy(isIdentifier) else { return nil }
        return path
    }

    private static func isIdentifier(_ text: Substring) -> Bool {
        guard let first = text.first, first.isLetter || first == "_" else { return false }
        return text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// One binary comparison, as source text.
    private struct Comparison {
        let lhs: String
        let operation: String
        let rhs: String
    }

    /// `lhs OP rhs` from an unfolded sequence or a folded infix expression.
    private static func comparison(_ expression: ExprSyntax) -> Comparison? {
        if let sequence = expression.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            guard elements.count == 3,
                  let binary = elements[1].as(BinaryOperatorExprSyntax.self) else { return nil }
            return Comparison(
                lhs: elements[0].trimmedDescription,
                operation: binary.operator.text,
                rhs: elements[2].trimmedDescription
            )
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self),
           let binary = infix.operator.as(BinaryOperatorExprSyntax.self) {
            return Comparison(
                lhs: infix.leftOperand.trimmedDescription,
                operation: binary.operator.text,
                rhs: infix.rightOperand.trimmedDescription
            )
        }
        return nil
    }
}
