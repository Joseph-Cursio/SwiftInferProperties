import SwiftSyntax

/// What the extended reader admitted (§2.4).
struct ExtendedRow: Codable {
    /// `identity-first`, `cut-first` or `ternary`.
    let form: String
    let counted: String
    /// The counted expression with the admitted `let`s inlined: the `e` Law 1 is stated over.
    let inlined: String
    let view: String
    let op: String
    let n: Int
    let constant: String
    /// Whether Law 1 fires when the condition holds (`true`) or when it does not.
    let lawWhenConditionHolds: Bool
    /// `b`, `c`, both, or neither.
    let needs: [String]
    /// Why (c) is needed: `lets`, `labelGate`, `bareStatic`, `typeName`.
    let cReasons: [String]
    let cut: String?
    let cutForm: String
    var isNew = false
    var walkEligible = false
}

/// The prototype reader the scope's §2.4 freezes. It lives only in this harness.
enum ExtendedReader {
    enum Outcome {
        case admitted(ExtendedRow)
        case refused(String)
        /// No count threshold anywhere this reader looks: not a near miss.
        case notApplicable
    }

    struct Context {
        let parameter: String
        let parameterType: String
        let statics: StaticConstants.Scope
        var bindings: [(name: String, value: ExprSyntax)] = []
        var cReasons: Set<String> = []

        var allowed: Set<String> { Set([parameter, "Self"] + bindings.map(\.name)) }
    }

    static func read(_ function: FunctionDeclSyntax, statics: StaticConstants.Scope) -> Outcome {
        let parameters = function.signature.parameterClause.parameters
        guard let statements = function.body?.statements.map(\.item), !statements.isEmpty else { return .notApplicable }
        guard hasThreshold(statements, statics: statics) else { return .notApplicable }
        guard parameters.count == 1, let parameter = parameters.first else { return .refused("not unary") }
        let name = (parameter.secondName ?? parameter.firstName).text
        guard name != "_" else { return .refused("unnamed parameter") }
        if let effects = function.signature.effectSpecifiers,
           effects.asyncSpecifier != nil || effects.throwsClause != nil {
            return .refused("async or throws")
        }
        if function.modifiers.contains(where: { $0.name.tokenKind == .keyword(.mutating) }) { return .refused("mutating") }
        guard let returnType = function.signature.returnClause?.type.trimmedDescription,
              returnType != "Void", returnType != "()" else { return .refused("no result") }
        var context = Context(parameter: name, parameterType: parameter.type.trimmedDescription, statics: statics)
        var index = 0
        while index < statements.count, let (binding, value) = letBinding(statements[index]) {
            if let refusal = gate(Syntax(value), &context) { return .refused("let \(binding): \(refusal)") }
            context.bindings.append((binding, value))
            index += 1
        }
        guard index < statements.count else { return .refused("no threshold after the lets") }
        if !context.bindings.isEmpty { context.cReasons.insert("lets") }
        return threshold(statements, at: index, context: &context)
    }

    // MARK: - The threshold statement

    private static func threshold(
        _ statements: [CodeBlockItemSyntax.Item],
        at index: Int,
        context: inout Context
    ) -> Outcome {
        let item = statements[index]
        let isLast = index == statements.count - 1
        if let guardStmt = item.as(GuardStmtSyntax.self) {
            guard let condition = single(guardStmt.conditions), let returned = soleReturn(guardStmt.body) else {
                return .refused("guard is not one predicate and one return")
            }
            guard let comparison = CountComparison.read(condition, statics: context.statics) else {
                return .refused("guard condition is not a count comparison")
            }
            guard returned.trimmedDescription == comparison.counted.trimmedDescription else {
                return .refused("guard returns the cut (cut-first guard, outside the frozen rules)")
            }
            return finish("identity-first", comparison, lawWhenHolds: false, cut: nil, context: &context)
        }
        if let ifExpr = item.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self) {
            guard ifExpr.elseBody == nil, let condition = single(ifExpr.conditions),
                  let returned = soleReturn(ifExpr.body) else {
                return .refused("if is not one predicate and one return, without else")
            }
            guard let comparison = CountComparison.read(condition, statics: context.statics) else {
                return .refused("if condition is not a count comparison")
            }
            let counted = comparison.counted.trimmedDescription
            if returned.trimmedDescription == counted {
                return finish("identity-first", comparison, lawWhenHolds: true, cut: nil, context: &context)
            }
            guard index == statements.count - 2,
                  let tail = statements[index + 1].as(ReturnStmtSyntax.self)?.expression,
                  tail.trimmedDescription == counted else {
                return .refused("cut-first if not followed by exactly `return \(counted)`")
            }
            return finish("cut-first", comparison, lawWhenHolds: false, cut: returned.trimmedDescription, context: &context)
        }
        let expression = item.as(ReturnStmtSyntax.self)?.expression
            ?? (statements.count == 1 ? item.as(ExpressionStmtSyntax.self)?.expression ?? item.as(ExprSyntax.self) : nil)
        guard isLast, let sequence = expression?.as(SequenceExprSyntax.self) else {
            return .refused("statement after the lets is not a threshold")
        }
        let elements = Array(sequence.elements)
        let ternaries = elements.indices.filter { elements[$0].is(UnresolvedTernaryExprSyntax.self) }
        guard ternaries.count == 1, let at = ternaries.first, at > 0, at < elements.count - 1,
              let ternary = elements[at].as(UnresolvedTernaryExprSyntax.self) else {
            return .refused("return is not one ternary")
        }
        guard let comparison = CountComparison.read(elements: Array(elements[..<at]), statics: context.statics) else {
            return .refused("ternary condition is not a count comparison")
        }
        let counted = comparison.counted.trimmedDescription
        let thenBranch = ternary.thenExpression
        let elseText = elements[(at + 1)...].map(\.trimmedDescription).joined(separator: " ")
        if thenBranch.trimmedDescription == counted {
            return finish("ternary", comparison, lawWhenHolds: true, cut: elseText, context: &context)
        }
        if elseText == counted {
            return finish("ternary", comparison, lawWhenHolds: false, cut: thenBranch.trimmedDescription, context: &context)
        }
        return .refused("neither ternary branch is the counted value")
    }

    private static func finish(
        _ form: String,
        _ comparison: CountComparison,
        lawWhenHolds: Bool,
        cut: String?,
        context: inout Context
    ) -> Outcome {
        if let refusal = gate(Syntax(comparison.counted), &context) { return .refused("counted value: \(refusal)") }
        if comparison.usesBareStatic { context.cReasons.insert("bareStatic") }
        if comparison.usesTypeName { context.cReasons.insert("typeName") }
        var needs: [String] = []
        if form != "identity-first" { needs.append("b") }
        if !context.cReasons.isEmpty { needs.append("c") }
        var row = ExtendedRow(
            form: form,
            counted: comparison.counted.trimmedDescription,
            inlined: inline(Syntax(comparison.counted), context.bindings),
            view: comparison.view,
            op: comparison.op,
            n: comparison.n,
            constant: comparison.constant,
            lawWhenConditionHolds: lawWhenHolds,
            needs: needs,
            cReasons: context.cReasons.sorted(),
            cut: cut,
            cutForm: cut.map(cutForm) ?? "none"
        )
        row.walkEligible = ["String", "Substring"].contains(context.parameterType)
            && WalkEligibility.isEligible(comparison.counted, context: context)
        return .admitted(row)
    }

    // MARK: - The gate (§2.4.1)

    /// `nil` when `node` mentions only allowed names; otherwise why not. Records which (c) reasons it used.
    static func gate(_ node: Syntax, _ context: inout Context) -> String? {
        let free = LabelAwareGate.freeNames(in: node).subtracting(context.allowed)
        var refused: [String] = []
        for name in free.sorted() {
            if name.drop(while: { $0 == "_" }).first?.isUppercase == true {
                context.cReasons.insert("typeName")
            } else if context.statics.values[name] != nil {
                context.cReasons.insert("bareStatic")
            } else {
                refused.append(name)
            }
        }
        if !refused.isEmpty { return "mentions \(refused.joined(separator: ", "))" }
        // Would today's text gate have refused it, over the same allowed names?
        let textFree = TextGate.freeNames(in: node.trimmedDescription, allowed: context.allowed, allowingTypeNames: true)
            .filter { context.statics.values[$0] == nil }
        if !textFree.isEmpty { context.cReasons.insert("labelGate") }
        return nil
    }

    // MARK: - Pieces

    static func letBinding(_ item: CodeBlockItemSyntax.Item) -> (String, ExprSyntax)? {
        guard let decl = item.as(VariableDeclSyntax.self), decl.bindingSpecifier.tokenKind == .keyword(.let),
              decl.bindings.count == 1, let binding = decl.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              let value = binding.initializer?.value else { return nil }
        return (name, value)
    }

    private static func single(_ conditions: ConditionElementListSyntax) -> ExprSyntax? {
        guard conditions.count == 1, case .expression(let expression)? = conditions.first?.condition else { return nil }
        return expression
    }

    private static func soleReturn(_ body: CodeBlockSyntax) -> ExprSyntax? {
        guard body.statements.count == 1 else { return nil }
        return body.statements.first?.item.as(ReturnStmtSyntax.self)?.expression
    }

    /// Whether any top-level `if`, `guard` or returned ternary compares a count with a constant: the functions
    /// whose refusals are near misses worth recording.
    private static func hasThreshold(_ statements: [CodeBlockItemSyntax.Item], statics: StaticConstants.Scope) -> Bool {
        statements.contains { item in
            if let guardStmt = item.as(GuardStmtSyntax.self) {
                return guardStmt.conditions.contains { element in
                    if case .expression(let expression) = element.condition {
                        return CountComparison.read(expression, statics: statics) != nil
                    }
                    return false
                }
            }
            if let ifExpr = item.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self) {
                return ifExpr.conditions.contains { element in
                    if case .expression(let expression) = element.condition {
                        return CountComparison.read(expression, statics: statics) != nil
                    }
                    return false
                }
            }
            let expression = item.as(ReturnStmtSyntax.self)?.expression ?? item.as(ExprSyntax.self)
            guard let elements = expression?.as(SequenceExprSyntax.self).map({ Array($0.elements) }),
                  let at = elements.firstIndex(where: { $0.is(UnresolvedTernaryExprSyntax.self) }) else { return false }
            return CountComparison.read(elements: Array(elements[..<at]), statics: statics) != nil
        }
    }

    static func cutForm(_ cut: String) -> String {
        let shape = if cut.contains(".prefix(") { "prefix" } else if cut.contains(".suffix(") { "suffix" }
            else if cut.contains(".dropLast(") { "dropLast" } else if cut.contains("[..<") { "slice" } else { "other" }
        let trimmed = cut.trimmingCharacters(in: .whitespaces)
        guard let plus = trimmed.range(of: "+ \"", options: .backwards) else { return shape }
        let marker = trimmed[plus.upperBound...]
        return shape + (marker.contains("\\(") ? " + interpolated marker" : " + marker")
    }

    /// `node`'s text with each admitted binding replaced by its (already inlined) initialiser.
    static func inline(_ node: Syntax, _ bindings: [(name: String, value: ExprSyntax)]) -> String {
        var values: [String: String] = [:]
        for (name, value) in bindings {
            values[name] = Inliner(values).rewrite(Syntax(value)).trimmedDescription
        }
        return Inliner(values).rewrite(node).trimmedDescription
    }

    private final class Inliner: SyntaxRewriter {
        let values: [String: String]

        init(_ values: [String: String]) {
            self.values = values
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
            if let member = node.parent?.as(MemberAccessExprSyntax.self), member.declName.id == node.id {
                return ExprSyntax(node)
            }
            guard let value = values[node.baseName.text] else { return ExprSyntax(node) }
            return ExprSyntax("(\(raw: value))").with(\.leadingTrivia, node.leadingTrivia)
                .with(\.trailingTrivia, node.trailingTrivia)
        }
    }
}
