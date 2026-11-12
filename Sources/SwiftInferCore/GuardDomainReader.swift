import SwiftParser
import SwiftSyntax

/// Reads the sub-domain a function's first statement carves out with an early return.
///
/// See `GuardDomain` for what the law means and why it is role-entailed. This is the syntactic
/// half: which shapes are admitted, and — more importantly — which are refused.
///
/// ## What is refused, and why each refusal is the whole precision
///
/// **An optional binding is not a domain claim.** `guard let x = y else { return nil }` says
/// nothing about the function's semantics; it propagates a `nil`. Measured over 3 358 functions:
/// 537 open with an early return and only 121 of those carry a *predicate* condition. Admitting
/// the binding forms would have made four fifths of the population noise.
///
/// **A condition the caller cannot evaluate is not a law.** `if trimmed.isEmpty` where `trimmed`
/// came from instance state is true of the object, not of the argument, so no test can state it
/// over a generated value. The condition must mention the parameter and nothing else free —
/// which is why a helper call like `isValidValue(value)` is also refused, however inviting: the
/// emitted test would have to reach a symbol that may not be visible to it.
///
/// **`guard` and `if` state opposite sub-domains.** `guard c else { return r }` yields `r` when
/// `c` is FALSE; `if c { return r }` when it is true. Recording which is `firesWhenConditionHolds`
/// rather than normalising at the call site, because an inverted law is worse than no law: it
/// would be checked over exactly the inputs it does not describe.
public enum GuardDomainReader {

    /// The domain `function`'s first statement carves out, or `nil`.
    ///
    /// Unary only. A multi-parameter guard is a law about one axis of a product and the emitter
    /// would have to generate the others to state it; that is a wider change than this shape
    /// earns, and the population it adds is 58 of 121 rather than the whole remainder.
    public static func read(_ function: FunctionDeclSyntax) -> GuardDomain? {
        let parameters = function.signature.parameterClause.parameters
        guard parameters.count == 1,
              let parameter = parameters.first else { return nil }
        let name = (parameter.secondName ?? parameter.firstName).text
        guard name != "_" else { return nil }

        guard let first = function.body?.statements.first?.item else { return nil }
        if let guardStmt = first.as(GuardStmtSyntax.self) {
            return domain(
                conditions: guardStmt.conditions,
                body: guardStmt.body,
                parameter: name,
                firesWhenConditionHolds: false
            )
        }
        if let expression = first.as(ExpressionStmtSyntax.self),
           let ifExpr = expression.expression.as(IfExprSyntax.self),
           ifExpr.elseBody == nil {
            return domain(
                conditions: ifExpr.conditions,
                body: ifExpr.body,
                parameter: name,
                firesWhenConditionHolds: true
            )
        }
        if function.body?.statements.count == 1 {
            return ternaryDomain(first, parameter: name)
        }
        return nil
    }

    /// The domain a body that is ONE ternary carves out — `cond ? literal : x`, or `return` of one.
    ///
    /// **The same law as an early return, written as an expression.** `name == "*" ? "[*]" : name`
    /// states `name == "*" ⟹ f(name) == "[*]"` exactly as `if name == "*" { return "[*]" }` would,
    /// and the reader saw only the statement forms, so the law was never proposed — and the two
    /// law-blind mutants in `docs/measurements/law-blind-mutants.md` that swap the literal went
    /// uncaught. The then-branch is the law, firing when the condition holds; when the then-branch
    /// is the parameter itself (`cond ? x : literal`), the else-branch is, firing when it does not.
    ///
    /// Unfolded syntax: the parser leaves `a ? b : c` as a sequence with an unresolved ternary in
    /// it, the condition before and the else-branch after. Only a single top-level ternary is read.
    private static func ternaryDomain(_ item: CodeBlockItemSyntax.Item, parameter: String) -> GuardDomain? {
        let expression = item.as(ReturnStmtSyntax.self)?.expression
            ?? item.as(ExpressionStmtSyntax.self)?.expression
            ?? item.as(ExprSyntax.self)
        guard let sequence = expression?.as(SequenceExprSyntax.self) else { return nil }
        let elements = Array(sequence.elements)
        let ternaries = elements.indices.filter { elements[$0].is(UnresolvedTernaryExprSyntax.self) }
        guard ternaries.count == 1, let index = ternaries.first, index > 0, index < elements.count - 1,
              let ternary = elements[index].as(UnresolvedTernaryExprSyntax.self) else { return nil }
        let conditionNodes = elements[..<index].map(Syntax.init)
        let elseNodes = elements[(index + 1)...].map(Syntax.init)
        let condition = elements[..<index].map(\.trimmedDescription).joined(separator: " ")
        let thenBranch = ternary.thenExpression.trimmedDescription
        let elseBranch = elements[(index + 1)...].map(\.trimmedDescription).joined(separator: " ")
        guard mentionsOnly(parameter, in: conditionNodes) else { return nil }
        let thenIsParameter = thenBranch == parameter
        let (returned, fires) = thenIsParameter ? (elseBranch, false) : (thenBranch, true)
        let returnedNodes = thenIsParameter ? elseNodes : [Syntax(ternary.thenExpression)]
        guard returned != parameter, !returned.isEmpty,
              mentionsOnly(parameter, in: returnedNodes, allowingTypeNames: true) else { return nil }
        return GuardDomain(
            condition: condition,
            returnedExpression: returned,
            parameterName: parameter,
            firesWhenConditionHolds: fires
        )
    }

    private static func domain(
        conditions: ConditionElementListSyntax,
        body: CodeBlockSyntax,
        parameter: String,
        firesWhenConditionHolds: Bool
    ) -> GuardDomain? {
        // Every element must be a plain expression: one `let` or `case` and this is a binding,
        // not a predicate.
        var expressions: [ExprSyntax] = []
        for element in conditions {
            guard case .expression(let expression) = element.condition else { return nil }
            expressions.append(expression)
        }
        guard !expressions.isEmpty else { return nil }
        let condition = expressions.map(\.trimmedDescription).joined(separator: " && ")
        guard mentionsOnly(parameter, in: expressions.map(Syntax.init)) else { return nil }

        guard body.statements.count == 1,
              let returnStmt = body.statements.first?.item.as(ReturnStmtSyntax.self),
              let returnedNode = returnStmt.expression else { return nil }
        let returned = returnedNode.trimmedDescription
        guard !returned.isEmpty else { return nil }
        // **The returned expression has to be writable at a call site too**, and checking only
        // the condition was the first version's gap. `guard node.catchClauses.isEmpty else {
        // return walkBlock(node.body.statements) }` has a perfectly evaluable condition and a
        // return that reaches a helper the emitted test cannot be assumed to see — which is the
        // uncompilable-stub shape this walk has spent its length closing. Type names are
        // permitted because a test that imports the module can name them; lowercase free
        // identifiers are not.
        guard mentionsOnly(parameter, in: [Syntax(returnedNode)], allowingTypeNames: true) else { return nil }

        return GuardDomain(
            condition: condition,
            returnedExpression: returned,
            parameterName: parameter,
            firesWhenConditionHolds: firesWhenConditionHolds
        )
    }

    /// Whether every free name in `nodes` is the parameter itself, `self` or `Self`, or, when
    /// `allowingTypeNames`, a type a test importing the module can name.
    ///
    /// Free is read off the syntax (`GuardDomainFreeNames`): an argument label, a member, a closure's
    /// own parameter and a word inside a string literal are not names, and `super`, a macro and a
    /// `$`-projection are. A call like `isValidValue(value)` still has two free names, so it is
    /// refused: the emitted test cannot be assumed to reach `isValidValue`.
    ///
    /// The first version scanned text and read any identifier not preceded by `.` as free. It refused
    /// labelled calls, and it admitted `user.id == $user.id`, reading the projection `$user` as the
    /// parameter `user` (`docs/measurements/guard-domain-syntax-gate.md`).
    static func mentionsOnly(_ parameter: String, in nodes: [Syntax], allowingTypeNames: Bool = false) -> Bool {
        var free = GuardDomainFreeNames.of(nodes)
        free.subtract([parameter, "self", "Self"])
        // A type name is judged past its leading underscores: `_AttributeStorage` is a type, which a
        // test importing the module can name, exactly as it can `AttributeStorage`. `_base` is not.
        if allowingTypeNames { free = free.filter { $0.drop { $0 == "_" }.first?.isUppercase != true } }
        return free.isEmpty
    }

    /// `mentionsOnly` over `text` parsed as an expression.
    static func mentionsOnly(_ parameter: String, in text: String, allowingTypeNames: Bool = false) -> Bool {
        mentionsOnly(parameter, in: [Syntax(Parser.parse(source: text))], allowingTypeNames: allowingTypeNames)
    }
}
