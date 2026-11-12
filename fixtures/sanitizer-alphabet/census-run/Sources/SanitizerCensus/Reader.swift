import SwiftOperators
import SwiftSyntax

struct Refusal: Error, Equatable {
    let reason: String
    init(_ reason: String) { self.reason = reason }
}

/// The reader `R` of `docs/plans/sanitizer-alphabet-census-scope.md` §2.2.
struct Reading: Codable, Equatable {
    var core = ""
    var preTransform = false
    var localSets: [String] = []
    var prefixRule = false
    var fallback = false
    var usesAnd = false
    var literals: [String] = []
    /// §2.3: law 1 reads only with no pre-transform and no prefix rule.
    var law1: Bool { !preTransform && !prefixRule }
}

enum Reader {
    static let preTransforms: Set<String> = ["lowercased", "uppercased", "trimmingCharacters"]
    static let properties: Set<String> = ["isLetter", "isNumber", "isASCII"]

    /// §2.1. `nil` when the shape passes, else the refusal.
    static func shapeRefusal(_ function: FunctionDeclSyntax) -> String? {
        let signature = function.signature
        if signature.effectSpecifiers?.asyncSpecifier != nil || signature.effectSpecifiers?.throwsClause != nil {
            return "shape"
        }
        if function.modifiers.contains(where: { $0.name.tokenKind == .keyword(.mutating) }) { return "shape" }
        guard signature.parameterClause.parameters.count == 1,
              let parameter = signature.parameterClause.parameters.first,
              parameter.type.as(IdentifierTypeSyntax.self)?.name.text == "String",
              signature.returnClause?.type.as(IdentifierTypeSyntax.self)?.name.text == "String" else { return "shape" }
        return nil
    }

    /// The state one read carries: the parameter, the pre-transform bindings and the local sets.
    struct Context {
        var inputs: Set<String>
        var sets: Set<String> = []
        var reading = Reading()
    }

    static func read(_ function: FunctionDeclSyntax) -> Result<Reading, Refusal> {
        guard shapeRefusal(function) == nil, let parameter = function.signature.parameterClause.parameters.first,
              let rawBody = function.body else { return .failure(Refusal("shape")) }
        let folded = OperatorTable.standardOperators.foldAll(rawBody) { _ in }
        guard let body = folded.as(CodeBlockSyntax.self) else { return .failure(Refusal("shape")) }
        var context = Context(inputs: [(parameter.secondName ?? parameter.firstName).text])
        var items = body.statements.map(\.item)[...]

        // Pre-steps.
        while let item = items.first, let decl = item.as(VariableDeclSyntax.self),
              decl.bindingSpecifier.tokenKind == .keyword(.let), decl.bindings.count == 1,
              let binding = decl.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              let value = binding.initializer?.value {
            if isInput(value, context: &context, allowScalars: false), value.is(FunctionCallExprSyntax.self) {
                context.inputs.insert(name)
                context.reading.preTransform = true
            } else if isLocalSet(value, annotation: binding.typeAnnotation?.type) {
                context.sets.insert(name)
                context.reading.localSets.append(value.trimmedDescription)
            } else {
                break
            }
            items = items.dropFirst()
        }

        // Core.
        guard let first = items.first else { return .failure(Refusal("core: none")) }
        var accumulator: String?
        var accumulatorIsVar = false
        if items.count == 1, let returned = returnedExpression(first) {
            // A directly returned F2/F3 expression.
            return readExpressionCore(returned, context: &context).map { _ in context.reading }
        }
        if let decl = first.as(VariableDeclSyntax.self), decl.bindings.count == 1, let binding = decl.bindings.first,
           let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
           let value = binding.initializer?.value {
            accumulator = name
            accumulatorIsVar = decl.bindingSpecifier.tokenKind == .keyword(.var)
            items = items.dropFirst()
            if accumulatorIsVar, ["\"\"", "String()"].contains(value.trimmedDescription) {
                guard let loop = items.first?.as(ForStmtSyntax.self) else { return .failure(Refusal("core: none")) }
                if case .failure(let refusal) = readLoop(loop, accumulator: name, context: &context) {
                    return .failure(refusal)
                }
                items = items.dropFirst()
            } else if case .failure(let refusal) = readExpressionCore(value, context: &context) {
                return .failure(refusal)
            }
        } else {
            return .failure(Refusal("core: none"))
        }
        guard let accumulator else { return .failure(Refusal("core: none")) }

        // Post-step: at most one prefix rule.
        if items.count == 2, accumulatorIsVar, let rule = ifExpression(items.first!) {
            guard isPrefixRule(rule, accumulator: accumulator, context: &context) else {
                return .failure(Refusal("post: other"))
            }
            context.reading.prefixRule = true
            items = items.dropFirst()
        }
        guard items.count == 1, let last = items.first, let returned = returnedExpression(last) else {
            return .failure(Refusal(items.count > 1 ? "post: other" : "return: other"))
        }
        if returned.as(DeclReferenceExprSyntax.self)?.baseName.text == accumulator { return .success(context.reading) }
        if let ternary = returned.as(TernaryExprSyntax.self),
           ternary.condition.trimmedDescription == "\(accumulator).isEmpty",
           let literal = stringLiteral(ternary.thenExpression),
           ternary.elseExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == accumulator {
            context.reading.fallback = true
            context.reading.literals.append(literal)
            return .success(context.reading)
        }
        return .failure(Refusal("return: other"))
    }

    // MARK: - Pieces

    static func returnedExpression(_ item: CodeBlockItemSyntax.Item) -> ExprSyntax? {
        if let statement = item.as(ReturnStmtSyntax.self) { return statement.expression }
        return item.as(ExprSyntax.self)
    }

    static func ifExpression(_ item: CodeBlockItemSyntax.Item) -> IfExprSyntax? {
        item.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self) ?? item.as(IfExprSyntax.self)
    }

    static func stringLiteral(_ expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self),
              literal.segments.allSatisfy({ $0.is(StringSegmentSyntax.self) }) else { return nil }
        return literal.segments.map(\.trimmedDescription).joined()
    }

    /// The parameter or a pre-transform binding, optionally through allowlisted calls and `.unicodeScalars`.
    static func isInput(_ expression: ExprSyntax, context: inout Context, allowScalars: Bool) -> Bool {
        if allowScalars, let member = expression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "unicodeScalars", let base = member.base {
            return isInput(base, context: &context, allowScalars: false)
        }
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return context.inputs.contains(reference.baseName.text)
        }
        guard let call = expression.as(FunctionCallExprSyntax.self), call.trailingClosure == nil,
              let callee = call.calledExpression.as(MemberAccessExprSyntax.self),
              preTransforms.contains(callee.declName.baseName.text), let base = callee.base else { return false }
        let name = callee.declName.baseName.text
        let argumentsOK = name == "trimmingCharacters"
            ? call.arguments.count == 1 && call.arguments.first?.label?.text == "in"
            : call.arguments.isEmpty
        guard argumentsOK, isInput(base, context: &context, allowScalars: false) else { return false }
        context.reading.preTransform = true
        return true
    }

    static func isCharacterSetExpression(_ expression: ExprSyntax) -> Bool {
        if let member = expression.as(MemberAccessExprSyntax.self) {
            if member.declName.baseName.text == "inverted", let base = member.base { return isCharacterSetExpression(base) }
            return member.base == nil || member.base?.trimmedDescription == "CharacterSet"
        }
        if let call = expression.as(FunctionCallExprSyntax.self) {
            if call.calledExpression.trimmedDescription == "CharacterSet", call.arguments.count == 1,
               call.arguments.first?.label?.text == "charactersIn",
               let argument = call.arguments.first?.expression, stringLiteral(argument) != nil { return true }
            if let callee = call.calledExpression.as(MemberAccessExprSyntax.self),
               callee.declName.baseName.text == "union", let base = callee.base, call.arguments.count == 1,
               let argument = call.arguments.first?.expression {
                return isCharacterSetExpression(base) && isCharacterSetExpression(argument)
            }
        }
        return false
    }

    static func isLocalSet(_ value: ExprSyntax, annotation: TypeSyntax?) -> Bool {
        if isCharacterSetExpression(value) { return true }
        if let call = value.as(FunctionCallExprSyntax.self), call.calledExpression.trimmedDescription.hasPrefix("Set"),
           call.arguments.count == 1, call.arguments.first?.label == nil, let argument = call.arguments.first?.expression {
            return stringLiteral(argument) != nil || isLiteralArray(argument)
        }
        if let annotation, annotation.trimmedDescription.hasPrefix("Set<"), isLiteralArray(value) { return true }
        return false
    }

    static func isLiteralArray(_ expression: ExprSyntax) -> Bool {
        guard let array = expression.as(ArrayExprSyntax.self) else { return false }
        return array.elements.allSatisfy { stringLiteral($0.expression) != nil }
    }

    /// `P` over `element` (§2.2).
    static func isPredicate(_ expression: ExprSyntax, element: String, context: inout Context) -> Bool {
        if let tuple = expression.as(TupleExprSyntax.self), tuple.elements.count == 1, let inner = tuple.elements.first {
            return isPredicate(inner.expression, element: element, context: &context)
        }
        if let prefix = expression.as(PrefixOperatorExprSyntax.self), prefix.operator.text == "!" {
            return isPredicate(prefix.expression, element: element, context: &context)
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self),
           let op = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text {
            switch op {
            case "||", "&&":
                if op == "&&" { context.reading.usesAnd = true }
                return isPredicate(infix.leftOperand, element: element, context: &context)
                    && isPredicate(infix.rightOperand, element: element, context: &context)

            case "==", "!=":
                let sides = [infix.leftOperand, infix.rightOperand]
                return sides.contains { isElement($0, element) } && sides.contains { stringLiteral($0) != nil }

            default:
                return false
            }
        }
        if let member = expression.as(MemberAccessExprSyntax.self), let base = member.base, isElement(base, element) {
            return properties.contains(member.declName.baseName.text)
        }
        if let call = expression.as(FunctionCallExprSyntax.self), call.trailingClosure == nil,
           let callee = call.calledExpression.as(MemberAccessExprSyntax.self),
           callee.declName.baseName.text == "contains", call.arguments.count == 1,
           call.arguments.first?.label == nil, let argument = call.arguments.first?.expression,
           isElement(argument, element), let base = callee.base {
            if let reference = base.as(DeclReferenceExprSyntax.self), context.sets.contains(reference.baseName.text) {
                return true
            }
            return isCharacterSetExpression(base)
        }
        return false
    }

    static func isElement(_ expression: ExprSyntax, _ element: String) -> Bool {
        expression.as(DeclReferenceExprSyntax.self)?.baseName.text == element
    }

    /// A closure's single parameter name, or `$0`, and its single expression.
    static func closureParts(_ closure: ClosureExprSyntax) -> (element: String, body: ExprSyntax)? {
        var element = "$0"
        switch closure.signature?.parameterClause {
        case .simpleInput(let parameters):
            guard parameters.count == 1, let only = parameters.first else { return nil }
            element = only.name.text

        case .parameterClause(let clause):
            guard clause.parameters.count == 1, let only = clause.parameters.first else { return nil }
            element = (only.secondName ?? only.firstName).text

        case nil:
            break
        }
        guard closure.statements.count == 1, let item = closure.statements.first?.item,
              let body = returnedExpression(item) else { return nil }
        return (element, body)
    }

    /// The closure or key path a `map` / `filter` call takes.
    static func callClosure(_ call: FunctionCallExprSyntax) -> ExprSyntax? {
        if let trailing = call.trailingClosure, call.arguments.isEmpty { return ExprSyntax(trailing) }
        if call.trailingClosure == nil, call.arguments.count == 1, call.arguments.first?.label == nil {
            return call.arguments.first?.expression
        }
        return nil
    }

    /// F2 and F3, as an expression (§2.2).
    static func readExpressionCore(_ expression: ExprSyntax, context: inout Context) -> Result<Void, Refusal> {
        var expression = expression
        var wrapped = false
        // `String(…)` and `String(String.UnicodeScalarView(…))`.
        while let call = expression.as(FunctionCallExprSyntax.self), call.trailingClosure == nil,
              ["String", "String.UnicodeScalarView"].contains(call.calledExpression.trimmedDescription),
              call.arguments.count == 1, call.arguments.first?.label == nil, let inner = call.arguments.first?.expression {
            expression = inner
            wrapped = true
        }
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let callee = call.calledExpression.as(MemberAccessExprSyntax.self), let base = callee.base,
              let argument = callClosure(call) else { return .failure(Refusal("core: none")) }
        let method = callee.declName.baseName.text
        guard method == "map" || method == "filter" else { return .failure(Refusal("core: none")) }
        guard isInput(base, context: &context, allowScalars: true) else { return .failure(Refusal("core: none")) }
        if method == "map", !wrapped { return .failure(Refusal("core: none")) }
        if let keyPath = argument.as(KeyPathExprSyntax.self) {
            guard method == "filter", keyPath.root == nil, keyPath.components.count == 1,
                  let component = keyPath.components.first?.component.as(KeyPathPropertyComponentSyntax.self),
                  properties.contains(component.declName.baseName.text) else {
                return .failure(Refusal("predicate: other"))
            }
            context.reading.core = "F3"
            return .success(())
        }
        guard let closure = argument.as(ClosureExprSyntax.self), let parts = closureParts(closure) else {
            return .failure(Refusal("core: none"))
        }
        if method == "filter" {
            guard isPredicate(parts.body, element: parts.element, context: &context) else {
                return .failure(Refusal("predicate: other"))
            }
            context.reading.core = "F3"
            return .success(())
        }
        guard let ternary = parts.body.as(TernaryExprSyntax.self), isElement(ternary.thenExpression, parts.element),
              let literal = stringLiteral(ternary.elseExpression) else { return .failure(Refusal("core: none")) }
        guard isPredicate(ternary.condition, element: parts.element, context: &context) else {
            return .failure(Refusal("predicate: other"))
        }
        context.reading.core = "F2"
        context.reading.literals.append(literal)
        return .success(())
    }

    /// F1's loop (§2.2).
    static func readLoop(_ loop: ForStmtSyntax, accumulator: String, context: inout Context) -> Result<Void, Refusal> {
        guard loop.whereClause == nil, loop.tryKeyword == nil, loop.awaitKeyword == nil,
              let element = loop.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              isInput(loop.sequence, context: &context, allowScalars: true) else {
            return .failure(Refusal("core: none"))
        }
        guard loop.body.statements.count == 1, let branch = ifExpression(loop.body.statements.first!.item),
              branch.conditions.count == 1, case .expression(let condition) = branch.conditions.first?.condition else {
            return .failure(Refusal("core: other statement in loop"))
        }
        guard isPredicate(condition, element: element, context: &context) else {
            return .failure(Refusal("predicate: other"))
        }
        guard branch.body.statements.count == 1,
              isVerbatimAppend(branch.body.statements.first!.item, accumulator: accumulator, element: element) else {
            return .failure(Refusal("core: other statement in loop"))
        }
        switch branch.elseBody {
        case nil:
            break

        case .codeBlock(let block):
            guard block.statements.count == 1,
                  let literal = literalAppend(block.statements.first!.item, accumulator: accumulator) else {
                return .failure(Refusal("core: other statement in loop"))
            }
            context.reading.literals.append(literal)

        case .ifExpr:
            return .failure(Refusal("core: other statement in loop"))
        }
        context.reading.core = "F1"
        return .success(())
    }

    static func isVerbatimAppend(_ item: CodeBlockItemSyntax.Item, accumulator: String, element: String) -> Bool {
        if let call = item.as(FunctionCallExprSyntax.self), call.trailingClosure == nil,
           let callee = call.calledExpression.as(MemberAccessExprSyntax.self), callee.declName.baseName.text == "append",
           call.arguments.count == 1, call.arguments.first?.label == nil, let argument = call.arguments.first?.expression {
            let target = callee.base?.trimmedDescription
            guard target == accumulator || target == "\(accumulator).unicodeScalars" else { return false }
            return argument.trimmedDescription == element || argument.trimmedDescription == "Character(\(element))"
        }
        if let infix = item.as(InfixOperatorExprSyntax.self),
           infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "+=",
           infix.leftOperand.trimmedDescription == accumulator {
            return ["String(\(element))", "String(Character(\(element)))"].contains(infix.rightOperand.trimmedDescription)
        }
        return false
    }

    static func literalAppend(_ item: CodeBlockItemSyntax.Item, accumulator: String) -> String? {
        if let infix = item.as(InfixOperatorExprSyntax.self),
           infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "+=",
           infix.leftOperand.trimmedDescription == accumulator {
            return stringLiteral(infix.rightOperand)
        }
        if let call = item.as(FunctionCallExprSyntax.self), call.trailingClosure == nil,
           let callee = call.calledExpression.as(MemberAccessExprSyntax.self), callee.declName.baseName.text == "append",
           callee.base?.trimmedDescription == accumulator, call.arguments.count == 1,
           call.arguments.first?.label == nil, let argument = call.arguments.first?.expression {
            return stringLiteral(argument)
        }
        return nil
    }

    /// `if <condition reading only acc> { acc = LIT + acc }`, no else.
    static func isPrefixRule(_ rule: IfExprSyntax, accumulator: String, context: inout Context) -> Bool {
        guard rule.elseBody == nil, rule.body.statements.count == 1,
              let assignment = rule.body.statements.first?.item.as(InfixOperatorExprSyntax.self),
              assignment.operator.is(AssignmentExprSyntax.self),
              assignment.leftOperand.trimmedDescription == accumulator,
              let concatenation = assignment.rightOperand.as(InfixOperatorExprSyntax.self),
              concatenation.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "+",
              let literal = stringLiteral(concatenation.leftOperand),
              concatenation.rightOperand.trimmedDescription == accumulator else { return false }
        var allowed: Set<String> = [accumulator]
        for element in rule.conditions {
            if case .optionalBinding(let binding) = element.condition,
               let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                allowed.insert(name)
            }
        }
        let referenced = rule.conditions.tokens(viewMode: .sourceAccurate).compactMap { token -> String? in
            guard case .identifier = token.tokenKind, let reference = token.parent?.as(DeclReferenceExprSyntax.self),
                  reference.parent?.as(MemberAccessExprSyntax.self)?.declName.id != reference.id else { return nil }
            return token.text
        }
        let bindingNames = rule.conditions.compactMap { element -> String? in
            if case .optionalBinding(let binding) = element.condition {
                return binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
            }
            return nil
        }
        guard referenced.allSatisfy({ allowed.contains($0) || bindingNames.contains($0) }) else { return false }
        context.reading.literals.append(literal)
        return true
    }
}
