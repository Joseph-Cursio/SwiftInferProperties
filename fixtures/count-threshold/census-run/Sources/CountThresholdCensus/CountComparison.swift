import SwiftSyntax

/// A condition that compares one count with an integer constant (§2.2), normalised so the count is on the left.
struct CountComparison {
    let counted: ExprSyntax
    let view: String
    let op: String
    let n: Int
    let constant: String
    let usesBareStatic: Bool
    let usesTypeName: Bool

    static let views: Set<String> = ["utf8", "utf16", "unicodeScalars"]
    static let flipped = [">": "<", "<": ">", ">=": "<=", "<=": ">="]

    /// The last length on one side and the first on the other.
    var boundary: (lo: Int, hi: Int) {
        switch op {
        case ">", "<=": (n, n + 1)
        default: (n - 1, n)
        }
    }

    /// Whether the comparison holds at counted length `length`.
    func holds(at length: Int) -> Bool {
        switch op {
        case ">": length > n
        case ">=": length >= n
        case "<": length < n
        default: length <= n
        }
    }

    /// Reads a condition given as one expression (a parenthesised one is unwrapped).
    static func read(_ expression: ExprSyntax, statics: StaticConstants.Scope) -> CountComparison? {
        var node = expression
        while let tuple = node.as(TupleExprSyntax.self), tuple.elements.count == 1,
              let only = tuple.elements.first, only.label == nil {
            node = only.expression
        }
        guard let sequence = node.as(SequenceExprSyntax.self) else { return nil }
        return read(elements: Array(sequence.elements), statics: statics)
    }

    /// Reads `lhs op rhs` from an unfolded sequence's elements.
    static func read(elements: [ExprSyntax], statics: StaticConstants.Scope) -> CountComparison? {
        guard elements.count == 3,
              let op = elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text,
              flipped[op] != nil else { return nil }
        if let (counted, view) = countAccess(elements[0]), let constant = constant(elements[2], statics: statics) {
            return CountComparison(
                counted: counted, view: view, op: op, n: constant.value, constant: elements[2].trimmedDescription,
                usesBareStatic: constant.bare, usesTypeName: constant.typeName
            )
        }
        if let (counted, view) = countAccess(elements[2]), let constant = constant(elements[0], statics: statics),
           let reversed = flipped[op] {
            return CountComparison(
                counted: counted, view: view, op: reversed, n: constant.value, constant: elements[0].trimmedDescription,
                usesBareStatic: constant.bare, usesTypeName: constant.typeName
            )
        }
        return nil
    }

    private static func countAccess(_ expression: ExprSyntax) -> (ExprSyntax, String)? {
        guard let member = expression.as(MemberAccessExprSyntax.self), member.declName.baseName.text == "count",
              member.declName.argumentNames == nil, let base = member.base else { return nil }
        if let inner = base.as(MemberAccessExprSyntax.self), views.contains(inner.declName.baseName.text),
           let innerBase = inner.base {
            return (innerBase, inner.declName.baseName.text + ".count")
        }
        return (base, "count")
    }

    private static func constant(
        _ expression: ExprSyntax,
        statics: StaticConstants.Scope
    ) -> (value: Int, bare: Bool, typeName: Bool)? {
        if let literal = expression.as(IntegerLiteralExprSyntax.self) {
            return Int(literal.literal.text.replacingOccurrences(of: "_", with: "")).map { ($0, false, false) }
        }
        if let member = expression.as(MemberAccessExprSyntax.self),
           let base = member.base?.as(DeclReferenceExprSyntax.self) {
            let owner = base.baseName.text
            let name = member.declName.baseName.text
            guard owner == "Self" || statics.typeNames.contains(owner), let value = statics.values[name] else {
                return nil
            }
            return (value, false, owner != "Self")
        }
        if let reference = expression.as(DeclReferenceExprSyntax.self),
           let value = statics.values[reference.baseName.text] {
            return (value, true, false)
        }
        return nil
    }
}

/// `static let k = <integer literal>` members, by the type that declares them in one file (§2.2).
struct StaticConstants {
    /// What a function in one type can name: the constants, and the spellings of the type itself.
    struct Scope {
        let values: [String: Int]
        let typeNames: Set<String>
        static let empty = Scope(values: [:], typeNames: [])
    }

    private(set) var byType: [String: [String: Int]] = [:]

    init(_ tree: SourceFileSyntax) {
        let collector = Collector(viewMode: .sourceAccurate)
        collector.walk(tree)
        byType = collector.byType
    }

    func scope(for typeName: String?) -> Scope {
        guard let typeName else { return .empty }
        let simple = String(typeName.split(separator: ".").last ?? Substring(typeName))
        return Scope(values: byType[simple] ?? [:], typeNames: [simple, typeName])
    }

    private final class Collector: SyntaxVisitor {
        var byType: [String: [String: Int]] = [:]

        override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
            guard node.bindingSpecifier.tokenKind == .keyword(.let),
                  node.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }),
                  let owner = Enclosing.of(Syntax(node)).typeName else { return .skipChildren }
            let simple = String(owner.split(separator: ".").last ?? Substring(owner))
            for binding in node.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let literal = binding.initializer?.value.as(IntegerLiteralExprSyntax.self),
                      let value = Int(literal.literal.text.replacingOccurrences(of: "_", with: "")) else { continue }
                byType[simple, default: [:]][name] = value
            }
            return .skipChildren
        }
    }
}

/// The declaration a node sits in.
struct Enclosing {
    /// `struct`, `class`, `enum`, `actor`, `extension`, `protocol`, `nested` (inside another body), or `free`.
    let kind: String
    let typeName: String?

    static func of(_ node: Syntax) -> Enclosing {
        var current = node.parent
        while let ancestor = current {
            if ancestor.is(FunctionDeclSyntax.self) || ancestor.is(ClosureExprSyntax.self)
                || ancestor.is(AccessorDeclSyntax.self) || ancestor.is(InitializerDeclSyntax.self) {
                return Enclosing(kind: "nested", typeName: nil)
            }
            if let decl = ancestor.as(StructDeclSyntax.self) { return Enclosing(kind: "struct", typeName: decl.name.text) }
            if let decl = ancestor.as(ClassDeclSyntax.self) { return Enclosing(kind: "class", typeName: decl.name.text) }
            if let decl = ancestor.as(EnumDeclSyntax.self) { return Enclosing(kind: "enum", typeName: decl.name.text) }
            if let decl = ancestor.as(ActorDeclSyntax.self) { return Enclosing(kind: "actor", typeName: decl.name.text) }
            if let decl = ancestor.as(ProtocolDeclSyntax.self) {
                return Enclosing(kind: "protocol", typeName: decl.name.text)
            }
            if let decl = ancestor.as(ExtensionDeclSyntax.self) {
                return Enclosing(kind: "extension", typeName: decl.extendedType.trimmedDescription)
            }
            current = ancestor.parent
        }
        return Enclosing(kind: "free", typeName: nil)
    }
}
