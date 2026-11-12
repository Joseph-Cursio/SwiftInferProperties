import SwiftSyntax

/// Today's text gate, copied from `GuardDomainReader.mentionsOnly` (it is not public), and the label-aware gate
/// the scope's §2.4.1 freezes.
enum TextGate {
    static func mentionsOnly(_ parameter: String, in condition: String, allowingTypeNames: Bool = false) -> Bool {
        freeNames(in: condition, allowed: [parameter], allowingTypeNames: allowingTypeNames).isEmpty
    }

    /// The free names today's scan reads in `text`: any identifier not preceded by a dot.
    static func freeNames(in text: String, allowed: Set<String>, allowingTypeNames: Bool) -> Set<String> {
        var free: Set<String> = []
        var previousWasDot = false
        var current = ""
        for character in withoutPlainStringLiterals(text) {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
                continue
            }
            if !current.isEmpty {
                if !previousWasDot, isName(current) { free.insert(current) }
                current = ""
            }
            previousWasDot = character == "."
        }
        if !current.isEmpty, !previousWasDot, isName(current) { free.insert(current) }
        free.subtract(allowed.union(["true", "false", "nil", "self", "Self"]))
        if allowingTypeNames { free = free.filter { $0.drop { $0 == "_" }.first?.isUppercase != true } }
        return free
    }

    static func isName(_ token: String) -> Bool {
        guard let first = token.first else { return false }
        return first.isLetter || (first == "_" && token.count > 1)
    }

    static func withoutPlainStringLiterals(_ text: String) -> String {
        text.replacingOccurrences(of: #""(?:[^"\\]|\\[^(])*""#, with: "\"\"", options: .regularExpression)
    }
}

/// The label-aware gate (§2.4.1): a `DeclReferenceExpr` is free unless it is a member, a key-path component, a
/// closure shorthand (`$0`), or a parameter of a closure inside the expression. Argument labels are not
/// `DeclReferenceExpr`s, so they are never free.
enum LabelAwareGate {
    static func freeNames(in nodes: [Syntax]) -> Set<String> {
        let collector = Collector(viewMode: .sourceAccurate)
        for node in nodes { collector.walk(node) }
        return collector.free
    }

    static func freeNames(in node: some SyntaxProtocol) -> Set<String> {
        freeNames(in: [Syntax(node)])
    }

    /// Today's gate with only the free-name reading changed: the same allowed names, type names only where
    /// today allows them.
    static func mentionsOnly(_ parameter: String, in nodes: [Syntax], allowingTypeNames: Bool = false) -> Bool {
        var free = freeNames(in: nodes)
        free.subtract([parameter, "self", "Self"])
        if allowingTypeNames { free = free.filter { $0.drop { $0 == "_" }.first?.isUppercase != true } }
        return free.isEmpty
    }

    private final class Collector: SyntaxVisitor {
        var free: Set<String> = []
        private var bound: [Set<String>] = []

        override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
            var names: Set<String> = []
            switch node.signature?.parameterClause {
            case .simpleInput(let list)?:
                for parameter in list { names.insert(parameter.name.text) }
            case .parameterClause(let clause)?:
                for parameter in clause.parameters { names.insert((parameter.secondName ?? parameter.firstName).text) }
            case nil:
                break
            }
            bound.append(names)
            return .visitChildren
        }

        override func visitPost(_ node: ClosureExprSyntax) {
            bound.removeLast()
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            if let member = node.parent?.as(MemberAccessExprSyntax.self), member.declName.id == node.id {
                return .skipChildren
            }
            if node.parent?.is(KeyPathPropertyComponentSyntax.self) == true { return .skipChildren }
            if case .dollarIdentifier = node.baseName.tokenKind { return .skipChildren }
            let name = node.baseName.text
            if bound.contains(where: { $0.contains(name) }) { return .skipChildren }
            free.insert(name)
            return .skipChildren
        }
    }
}
