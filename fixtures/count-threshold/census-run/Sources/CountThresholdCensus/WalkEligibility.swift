import SwiftSyntax

/// Whether the counted value is the parameter, or a chain over it whose every step is the identity on
/// letters-and-digits input (§2.5), so a walk's drawn length is the counted length.
enum WalkEligibility {
    static let whitespaceSets: Set<String> = ["whitespaces", "whitespacesAndNewlines"]

    static func isEligible(_ expression: ExprSyntax, context: ExtendedReader.Context) -> Bool {
        var node = expression
        while let tuple = node.as(TupleExprSyntax.self), tuple.elements.count == 1, let only = tuple.elements.first,
              only.label == nil {
            node = only.expression
        }
        if let reference = node.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            if name == context.parameter { return true }
            if let value = context.bindings.last(where: { $0.name == name })?.value {
                return isEligible(value, context: context)
            }
            return false
        }
        guard let call = node.as(FunctionCallExprSyntax.self) else { return false }
        if call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "String",
           call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil {
            return isEligible(argument.expression, context: context)
        }
        guard let member = call.calledExpression.as(MemberAccessExprSyntax.self), let base = member.base else {
            return false
        }
        let arguments = Array(call.arguments)
        switch member.declName.baseName.text {
        case "trimmingCharacters":
            guard arguments.count == 1, arguments[0].label?.text == "in", isWhitespaceSet(arguments[0].expression) else {
                return false
            }
            return isEligible(base, context: context)

        case "replacingOccurrences":
            guard arguments.count == 2, arguments[0].label?.text == "of", arguments[1].label?.text == "with",
                  isWhitespaceLiteral(arguments[0].expression), isWhitespaceLiteral(arguments[1].expression) else {
                return false
            }
            return isEligible(base, context: context)

        case "joined":
            guard arguments.count == 1, arguments[0].label?.text == "separator",
                  arguments[0].expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue == " ",
                  let filter = base.as(FunctionCallExprSyntax.self), isNonEmptyFilter(filter),
                  let filterBase = filter.calledExpression.as(MemberAccessExprSyntax.self)?.base,
                  let split = filterBase.as(FunctionCallExprSyntax.self),
                  let splitMember = split.calledExpression.as(MemberAccessExprSyntax.self),
                  splitMember.declName.baseName.text == "components", let splitBase = splitMember.base,
                  split.arguments.count == 1, split.arguments.first?.label?.text == "separatedBy",
                  let set = split.arguments.first?.expression, isWhitespaceSet(set) else {
                return false
            }
            return isEligible(splitBase, context: context)

        default:
            return false
        }
    }

    private static func isWhitespaceSet(_ expression: ExprSyntax) -> Bool {
        guard let member = expression.as(MemberAccessExprSyntax.self),
              whitespaceSets.contains(member.declName.baseName.text) else { return false }
        return member.base == nil || member.base?.trimmedDescription == "CharacterSet"
    }

    private static func isWhitespaceLiteral(_ expression: ExprSyntax) -> Bool {
        guard let value = expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else { return false }
        return value.allSatisfy(\.isWhitespace)
    }

    private static func isNonEmptyFilter(_ call: FunctionCallExprSyntax) -> Bool {
        guard call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "filter" else {
            return false
        }
        let closure = call.trailingClosure ?? call.arguments.first?.expression.as(ClosureExprSyntax.self)
        return closure?.statements.trimmedDescription == "!$0.isEmpty"
    }
}
