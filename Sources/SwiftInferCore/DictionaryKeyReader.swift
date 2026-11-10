import SwiftSyntax

/// Reads which member of a sorted array's elements holds the key of the `Dictionary` the array was
/// mapped from (SwiftInferProperties#647, law 2).
///
/// ```swift
/// var totals: [String: (violations: Int, repos: Int)] = [:]
/// …
/// return totals
///     .map { RuleHotspot(rule: $0.key, violations: $0.value.violations, repoCount: $0.value.repos) }
///     .sorted { $0.violations > $1.violations }
/// ```
///
/// reads `rule`. A dictionary iterates in hash order, and Swift seeds that order per table, so
/// whatever the comparator calls tied — two rules with equal `violations` — comes out in an order
/// the input does not decide. The keys are distinct, so the sequence of `rule` values is the whole
/// order, and comparing it across a permuted input is what `input-order-independence` checks.
///
/// Three things have to be read, and each is declined rather than approximated:
///
/// - **the receiver of `.sorted` is `.map { … }` or `.compactMap { … }`** over a dictionary —
///   `Dictionary(…)` spelled inline, or a body-level local declared `[K: V]`, initialised `[:]`,
///   `[K: V]()` or `Dictionary(…)`;
/// - **the closure names the key**: `{ key, value in … }`, `{ (key, value) in … }`, `{ entry in
///   … entry.key … }`, or `$0.key`;
/// - **what the closure returns passes the key to exactly one labelled argument** — a call, the
///   memberwise initializer's case, or a labelled tuple. That label is the element's member.
///
/// `dict.values.sorted { … }` is not read: nothing says which member of a value holds its key.
public enum DictionaryKeyReader {

    /// The element member holding the dictionary key, or `nil`.
    public static func keyMember(ofSortedCall expression: ExprSyntax, dictionaries: Set<String>) -> String? {
        guard let sortedCall = expression.as(FunctionCallExprSyntax.self),
              let sortedCallee = sortedCall.calledExpression.as(MemberAccessExprSyntax.self),
              let mapCall = sortedCallee.base?.as(FunctionCallExprSyntax.self),
              let mapCallee = mapCall.calledExpression.as(MemberAccessExprSyntax.self),
              ["map", "compactMap"].contains(mapCallee.declName.baseName.text),
              let dictionary = mapCallee.base,
              isDictionary(dictionary, locals: dictionaries),
              let closure = onlyClosure(of: mapCall),
              let key = keyReference(in: closure),
              let returned = returnedExpression(of: closure) else {
            return nil
        }
        return label(passing: key, in: returned)
    }

    /// Names of the body-level locals that hold a dictionary.
    public static func dictionaryLocals(in statements: CodeBlockItemListSyntax) -> Set<String> {
        var names: Set<String> = []
        for statement in statements {
            guard let declaration = statement.item.as(VariableDeclSyntax.self) else { continue }
            for binding in declaration.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
                    continue
                }
                if let type = binding.typeAnnotation?.type, isDictionaryType(type) {
                    names.insert(name)
                } else if let value = binding.initializer?.value, isDictionaryValue(value) {
                    names.insert(name)
                }
            }
        }
        return names
    }

    private static func isDictionary(_ expression: ExprSyntax, locals: Set<String>) -> Bool {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return locals.contains(reference.baseName.text)
        }
        return isDictionaryValue(expression)
    }

    /// `[:]`, `[K: V]()`, `Dictionary(…)` or `Dictionary<K, V>(…)`.
    private static func isDictionaryValue(_ expression: ExprSyntax) -> Bool {
        if let literal = expression.as(DictionaryExprSyntax.self) {
            if case .colon = literal.content { return true }
            return false
        }
        guard let call = expression.as(FunctionCallExprSyntax.self) else { return false }
        let callee = call.calledExpression
        if callee.is(DictionaryExprSyntax.self) { return true }
        if let specialised = callee.as(GenericSpecializationExprSyntax.self) {
            return specialised.expression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Dictionary"
        }
        return callee.as(DeclReferenceExprSyntax.self)?.baseName.text == "Dictionary"
    }

    /// `[K: V]` or `Dictionary<K, V>`.
    private static func isDictionaryType(_ type: TypeSyntax) -> Bool {
        if type.is(DictionaryTypeSyntax.self) { return true }
        return type.as(IdentifierTypeSyntax.self)?.name.text == "Dictionary"
    }

    /// The trailing closure, or a sole unlabelled closure argument.
    private static func onlyClosure(of call: FunctionCallExprSyntax) -> ClosureExprSyntax? {
        if let trailing = call.trailingClosure {
            return call.arguments.isEmpty && call.additionalTrailingClosures.isEmpty ? trailing : nil
        }
        guard call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil else {
            return nil
        }
        return argument.expression.as(ClosureExprSyntax.self)
    }

    /// How the closure spells the key: `key` for `{ key, value in }`, `entry.key` for `{ entry in }`,
    /// `$0.key` with no signature.
    private static func keyReference(in closure: ClosureExprSyntax) -> String? {
        let names: [String]
        switch closure.signature?.parameterClause {
        case .simpleInput(let list):
            names = list.map(\.name.text)

        case .parameterClause(let clause):
            names = clause.parameters.map { ($0.secondName ?? $0.firstName).text }

        case nil:
            return "$0.key"
        }
        switch names.count {
        case 1: return names[0] + ".key"
        case 2: return names[0] == "_" ? nil : names[0]
        default: return nil
        }
    }

    /// What the closure returns: its only expression, or its last statement's `return`.
    private static func returnedExpression(of closure: ClosureExprSyntax) -> ExprSyntax? {
        guard let last = closure.statements.last?.item else { return nil }
        if let returnStmt = last.as(ReturnStmtSyntax.self) { return returnStmt.expression }
        guard closure.statements.count == 1 else { return nil }
        return last.as(ExpressionStmtSyntax.self)?.expression ?? last.as(ExprSyntax.self)
    }

    /// The label of the one argument — or labelled tuple element — whose value is the key.
    private static func label(passing key: String, in expression: ExprSyntax) -> String? {
        let labelled: [(label: String?, value: String)]
        if let call = expression.as(FunctionCallExprSyntax.self) {
            labelled = call.arguments.map { ($0.label?.text, $0.expression.trimmedDescription) }
        } else if let tuple = expression.as(TupleExprSyntax.self), tuple.elements.count > 1 {
            labelled = tuple.elements.map { ($0.label?.text, $0.expression.trimmedDescription) }
        } else {
            return nil
        }
        let matches = labelled.filter { $0.value == key }
        guard matches.count == 1, let label = matches.first?.label else { return nil }
        return label
    }
}
