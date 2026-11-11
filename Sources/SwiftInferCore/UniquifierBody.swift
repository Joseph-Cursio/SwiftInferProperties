import SwiftSyntax

/// Collects every node it walks, in source order.
private final class NodeCollector: SyntaxAnyVisitor {
    private(set) var nodes: [Syntax] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        nodes.append(node)
        return .visitChildren
    }
}

/// One function body, prepared for `UniquifierShapeReader`: every node in source order, and which names
/// are stored state rather than locals or parameters (`uniquifier-law-census-scope.md` §1.2, *Stored*).
struct UniquifierBody {
    /// The collections `inout` may carry, so a parameter of one counts as stored state.
    static let collectionTypes: Set<String> = [
        "Array", "Set", "Dictionary", "OrderedSet", "OrderedDictionary", "ContiguousArray",
    ]

    /// Every node of the body, in source order.
    let nodes: [Syntax]
    /// The body's statements.
    let statements: CodeBlockItemListSyntax
    /// Names the body declares with `let`, `var` or `for`.
    let locals: Set<String>
    /// Every parameter's internal name.
    let parameters: Set<String>
    /// The parameters that are `inout` collections.
    let inoutCollections: Set<String>

    init?(function: FunctionDeclSyntax) {
        guard let body = function.body else { return nil }
        let collector = NodeCollector()
        collector.walk(body)
        nodes = collector.nodes
        statements = body.statements
        var names: Set<String> = []
        var inouts: Set<String> = []
        for parameter in function.signature.parameterClause.parameters {
            let name = (parameter.secondName ?? parameter.firstName).text
            names.insert(name)
            if Self.isInoutCollection(parameter.type.trimmedDescription) {
                inouts.insert(name)
            }
        }
        parameters = names
        inoutCollections = inouts
        locals = Self.declaredNames(in: collector.nodes)
    }

    /// Stored state: not declared in the body, and not a parameter unless an `inout` collection.
    func isStored(_ name: String) -> Bool {
        !locals.contains(name) && (!parameters.contains(name) || inoutCollections.contains(name))
    }

    /// `self.names?.values` → `names.values`. `nil` for anything but a plain chain of names.
    static func chain(_ expression: ExprSyntax) -> String? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        if let optional = expression.as(OptionalChainingExprSyntax.self) {
            return chain(optional.expression)
        }
        if let forced = expression.as(ForceUnwrapExprSyntax.self) {
            return chain(forced.expression)
        }
        if let member = expression.as(MemberAccessExprSyntax.self), let base = member.base,
           let head = chain(base) {
            let name = member.declName.baseName.text
            return head == "self" ? name : head + "." + name
        }
        return nil
    }

    /// A chain's first component: `existing.values` → `existing`.
    static func base(of chain: String) -> String {
        String(chain.prefix { $0 != "." })
    }

    /// `true` when `inner` lies within `outer`.
    static func isInside(_ inner: some SyntaxProtocol, _ outer: some SyntaxProtocol) -> Bool {
        inner.position >= outer.position && inner.endPosition <= outer.endPosition
    }

    /// The identifier tokens of `node` not reached through a `.`: in `a.b(c)`, `a` and `c`.
    static func freeNames(in node: some SyntaxProtocol) -> Set<String> {
        var names: Set<String> = []
        for token in node.tokens(viewMode: .sourceAccurate) {
            guard case .identifier(let text) = token.tokenKind else { continue }
            if token.previousToken(viewMode: .sourceAccurate)?.tokenKind != .period {
                names.insert(text)
            }
        }
        return names
    }

    /// The statement holding `node`: its nearest enclosing `CodeBlockItemSyntax`.
    static func statement(of node: some SyntaxProtocol) -> CodeBlockItemSyntax? {
        var current = node.parent
        while let candidate = current {
            if let item = candidate.as(CodeBlockItemSyntax.self) { return item }
            current = candidate.parent
        }
        return nil
    }

    private static func isInoutCollection(_ type: String) -> Bool {
        guard type.hasPrefix("inout ") else { return false }
        let kind = type.dropFirst("inout ".count).drop { $0 == " " }
        if kind.hasPrefix("["), kind.hasSuffix("]") { return true }
        let head = kind.prefix { $0 != "<" && $0 != " " }
        return collectionTypes.contains(String(head.split(separator: ".").last ?? head))
    }

    private static func declaredNames(in nodes: [Syntax]) -> Set<String> {
        var names: Set<String> = []
        for node in nodes {
            if let binding = node.as(PatternBindingSyntax.self),
               let name = binding.pattern.as(IdentifierPatternSyntax.self) {
                names.insert(name.identifier.text)
            } else if let condition = node.as(OptionalBindingConditionSyntax.self),
                      let name = condition.pattern.as(IdentifierPatternSyntax.self) {
                names.insert(name.identifier.text)
            } else if let loop = node.as(ForStmtSyntax.self),
                      let name = loop.pattern.as(IdentifierPatternSyntax.self) {
                names.insert(name.identifier.text)
            }
        }
        return names
    }
}
