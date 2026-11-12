import SwiftSyntax

/// The names in a `guard-domain` condition or returned expression that a test would have to supply,
/// read off the syntax.
///
/// ## Why syntax and not text
///
/// The first gate scanned text: any identifier not preceded by `.` was free. Text cannot tell an
/// argument label from a name, nor a word inside a string literal from code. So `contains(anyOf:)`,
/// `isIdentical(to:)`, a memberwise initialiser's labels, `"it extends \(name)"` and the keyword
/// `unsafe` all refused sites whose every name a stub can bind: 27, 4 and 2 of the 35 such rows over
/// 31,016 functions (`docs/measurements/guard-domain-syntax-gate.md`). Text also read `$user`, a
/// property-wrapper projection on the receiver, as the parameter `user`. That admitted
/// `user.id == $user.id`, a law about the object rather than the argument.
///
/// ## What is free
///
/// - every `DeclReferenceExpr` that is not a member (`x.count`), a key-path component (`\.count`), a
///   closure's shorthand parameter (`$0`), or a parameter of a closure inside the expression;
/// - `super`, which no test can call;
/// - a macro expansion (`#line`), whose value depends on where it is written;
/// - every type the expression names (`Foo` in `x is Foo`), which the caller filters when type
///   names are allowed.
///
/// A `$`-prefixed projection keeps its `$`, so `$user` never matches the parameter `user`.
/// `self` and `Self` are reported like any other name; the caller decides whether they are allowed.
enum GuardDomainFreeNames {

    static func of(_ nodes: [Syntax]) -> Set<String> {
        let collector = Collector(viewMode: .sourceAccurate)
        for node in nodes { collector.walk(node) }
        return collector.free
    }

    private final class Collector: SyntaxVisitor {
        var free: Set<String> = []
        private var bound: [Set<String>] = []

        override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
            var names: Set<String> = []
            switch node.signature?.parameterClause {
            case .simpleInput(let parameters):
                for parameter in parameters { names.insert(parameter.name.text) }

            case .parameterClause(let clause):
                for parameter in clause.parameters { names.insert((parameter.secondName ?? parameter.firstName).text) }

            case nil:
                break
            }
            bound.append(names)
            return .visitChildren
        }

        override func visitPost(_: ClosureExprSyntax) {
            bound.removeLast()
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            if let member = node.parent?.as(MemberAccessExprSyntax.self), member.declName.id == node.id {
                return .skipChildren
            }
            if node.parent?.is(KeyPathPropertyComponentSyntax.self) == true { return .skipChildren }
            if case .dollarIdentifier = node.baseName.tokenKind { return .skipChildren }
            let name = node.baseName.text
            if !bound.contains(where: { $0.contains(name) }) { free.insert(name) }
            return .skipChildren
        }

        override func visit(_: SuperExprSyntax) -> SyntaxVisitorContinueKind {
            free.insert("super")
            return .skipChildren
        }

        override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
            free.insert("#" + node.macroName.text)
            return .visitChildren
        }

        override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
            free.insert(node.name.text)
            return .visitChildren
        }
    }
}
