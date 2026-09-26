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
        return nil
    }

    private static func domain(
        conditions: ConditionElementListSyntax,
        body: CodeBlockSyntax,
        parameter: String,
        firesWhenConditionHolds: Bool
    ) -> GuardDomain? {
        // Every element must be a plain expression: one `let` or `case` and this is a binding,
        // not a predicate.
        var texts: [String] = []
        for element in conditions {
            guard case .expression(let expression) = element.condition else { return nil }
            texts.append(expression.trimmedDescription)
        }
        guard !texts.isEmpty else { return nil }
        let condition = texts.joined(separator: " && ")
        guard mentionsOnly(parameter, in: condition) else { return nil }

        guard body.statements.count == 1,
              let returnStmt = body.statements.first?.item.as(ReturnStmtSyntax.self),
              let returned = returnStmt.expression?.trimmedDescription,
              !returned.isEmpty else { return nil }
        // **The returned expression has to be writable at a call site too**, and checking only
        // the condition was the first version's gap. `guard node.catchClauses.isEmpty else {
        // return walkBlock(node.body.statements) }` has a perfectly evaluable condition and a
        // return that reaches a helper the emitted test cannot be assumed to see — which is the
        // uncompilable-stub shape this walk has spent its length closing. Type names are
        // permitted because a test that imports the module can name them; lowercase free
        // identifiers are not.
        guard mentionsOnly(parameter, in: returned, allowingTypeNames: true) else { return nil }

        return GuardDomain(
            condition: condition,
            returnedExpression: returned,
            parameterName: parameter,
            firesWhenConditionHolds: firesWhenConditionHolds
        )
    }

    /// Whether every free identifier in `condition` is the parameter itself.
    ///
    /// Free means *not* preceded by a dot: `value.isEmpty` has one free identifier, `value`, and
    /// `isEmpty` is a member of it. A call like `isValidValue(value)` has two, so it is refused —
    /// the emitted test cannot be assumed to reach `isValidValue`.
    ///
    /// Literals and the keywords a condition may legitimately carry are not identifiers for this
    /// purpose.
    static func mentionsOnly(
        _ parameter: String,
        in condition: String,
        allowingTypeNames: Bool = false
    ) -> Bool {
        var free: Set<String> = []
        var previousWasDot = false
        var current = ""
        for character in withoutPlainStringLiterals(condition) {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
                continue
            }
            if !current.isEmpty {
                if !previousWasDot, current.first?.isLetter == true { free.insert(current) }
                current = ""
            }
            previousWasDot = character == "."
        }
        if !current.isEmpty, !previousWasDot, current.first?.isLetter == true { free.insert(current) }
        free.subtract([parameter, "true", "false", "nil", "self", "Self"])
        if allowingTypeNames { free = free.filter { $0.first?.isUppercase != true } }
        return free.isEmpty
    }

    /// `text` with every string literal that interpolates nothing emptied to `""`.
    ///
    /// **A word inside quotes is not a name.** `return "relates"` was refused because the scan read
    /// `relates` as a free identifier, so every guard returning a word literal — and every ternary
    /// swapping one in (`raw.isEmpty ? "relates" : raw`) — was invisible to the law. A literal that
    /// interpolates keeps its text: `"\(name)!"` does reach `name`.
    static func withoutPlainStringLiterals(_ text: String) -> String {
        text.replacingOccurrences(
            of: #""(?:[^"\\]|\\[^(])*""#,
            with: "\"\"",
            options: .regularExpression
        )
    }
}
