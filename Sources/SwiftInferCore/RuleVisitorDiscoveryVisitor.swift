import SwiftSyntax

/// PROTOTYPE — single-pass walker collecting per-type lint-rule-visitor
/// info for one source file. Tracks an enclosing-type stack so members in
/// `class` / `extension` blocks attribute to the right type name (a
/// visitor's `visit(_:)` overrides routinely live in extensions across
/// files, e.g. `AccessibilityVisitor+Calls.swift`). A type's declaration
/// location + inherited types are recorded only from the `ClassDeclSyntax`;
/// `visit(_:)` overrides and `ruleName:` emissions merge from every source.
final class RuleVisitorDiscoveryVisitor: SyntaxVisitor {

    private(set) var collected: [String: RawVisitorInfo] = [:]
    private let file: String
    private let converter: SourceLocationConverter
    private var typeStack: [String] = []

    init(file: String, converter: SourceLocationConverter) {
        self.file = file
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Type-stack maintenance

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        typeStack.append(name)
        let line = converter.location(
            for: node.name.positionAfterSkippingLeadingTrivia
        ).line
        collected[name, default: RawVisitorInfo()].declLocation = "\(file):\(line)"
        if let inherited = node.inheritanceClause?.inheritedTypes {
            collected[name, default: RawVisitorInfo()].inheritedTypes =
                inherited.map(\.type.trimmedDescription)
        }
        return .visitChildren
    }
    override func visitPost(_: ClassDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.extendedType.trimmedDescription)
        return .visitChildren
    }
    override func visitPost(_: ExtensionDeclSyntax) { typeStack.removeLast() }

    // Push struct/enum/actor too, so a stray `visit`/`ruleName:` inside one
    // isn't mis-attributed to an enclosing visitor class. They never set a
    // declLocation (only ClassDecl does), so they can't become candidates.
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text); return .visitChildren
    }
    override func visitPost(_: StructDeclSyntax) { typeStack.removeLast() }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text); return .visitChildren
    }
    override func visitPost(_: EnumDeclSyntax) { typeStack.removeLast() }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text); return .visitChildren
    }
    override func visitPost(_: ActorDeclSyntax) { typeStack.removeLast() }

    // MARK: - The visitor signal: visit(_:) -> SyntaxVisitorContinueKind

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let typeName = typeStack.last, node.name.text == "visit" else {
            return .visitChildren
        }
        let returnType = node.signature.returnClause?.type.trimmedDescription
        guard returnType == "SyntaxVisitorContinueKind",
              let nodeType = node.signature.parameterClause.parameters
                  .first?.type.trimmedDescription else {
            return .visitChildren
        }
        collected[typeName, default: RawVisitorInfo()].visitedNodeTypes.insert(nodeType)
        // Walk the body — `addIssue(ruleName:)` emissions live inside it.
        return .visitChildren
    }

    // MARK: - Emitted rule identifiers (any `ruleName:` argument)

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let typeName = typeStack.last else { return .visitChildren }
        for argument in node.arguments where argument.label?.text == "ruleName" {
            var text = argument.expression.trimmedDescription
            if text.hasPrefix(".") { text = String(text.dropFirst()) }
            collected[typeName, default: RawVisitorInfo()].emittedRuleNames.insert(text)
        }
        return .visitChildren
    }
}

// MARK: - Per-type accumulator

/// Mutable per-type info gathered across the class declaration + all its
/// extensions. `declLocation` / `inheritedTypes` come only from the class
/// decl; `visitedNodeTypes` + `emittedRuleNames` merge from every source.
/// A type is a candidate iff it has a `declLocation` (it's a class) AND a
/// non-empty `visitedNodeTypes` (it overrides ≥1 `visit(_:)`).
struct RawVisitorInfo {
    var declLocation: String?
    var inheritedTypes: [String] = []
    var visitedNodeTypes: Set<String> = []
    var emittedRuleNames: Set<String> = []

    mutating func merge(_ other: Self) {
        declLocation = declLocation ?? other.declLocation
        if inheritedTypes.isEmpty { inheritedTypes = other.inheritedTypes }
        visitedNodeTypes.formUnion(other.visitedNodeTypes)
        emittedRuleNames.formUnion(other.emittedRuleNames)
    }
}
