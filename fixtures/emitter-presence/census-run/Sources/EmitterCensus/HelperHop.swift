import Foundation
import SwiftOperators
import SwiftSyntax

/// §2.6: resolve a helper call by name within the repository and decide whether the helper writes the argument
/// that carries the tracked value, following at most 2 hops.
enum HelperHop {
    static func resolve(_ call: FunctionCallExprSyntax, tracked: Set<String>, index: FunctionIndex, depth: Int) -> HelperRead {
        let name = Reader.calleeName(call) ?? call.calledExpression.trimmedDescription
        var read = HelperRead(chain: [name])
        let (found, reason) = index.resolve(call)
        guard let target = found else { read.reason = reason; return read }
        guard let argumentIndex = call.arguments.enumerated().first(where: { mentions($0.element.expression, tracked) })?.offset,
              let parameter = FunctionIndex.parameterName(for: argumentIndex, in: call, target.decl) else {
            read.reason = "argument not mapped to a parameter"
            return read
        }
        guard let rawBody = target.decl.body,
              let body = OperatorTable.standardOperators.foldAll(rawBody, errorHandler: { _ in }).as(CodeBlockSyntax.self)
        else { read.reason = "no body"; return read }
        let names = trackedNames(in: body, root: parameter)
        if let (template, transform) = writeSite(in: body, names: names) {
            read.resolved = true
            read.template = template
            read.transform = transform
            return read
        }
        if depth < 2 {
            for inner in CallCollector.collect(body) where mentions(inner, names) {
                let next = resolve(inner, tracked: names, index: index, depth: depth + 1)
                if next.resolved {
                    read.resolved = true
                    read.chain += next.chain
                    read.template = next.template
                    read.transform = next.transform
                    return read
                }
            }
            read.reason = "does not write \(parameter) within 2 hops"
        } else {
            read.reason = "does not write \(parameter); hop limit"
        }
        return read
    }

    static func mentions(_ node: some SyntaxProtocol, _ names: Set<String>) -> Bool {
        return NameReadFinder.reads(Syntax(node), names)
    }

    /// The parameter, plus loop variables over a path of it and `let`s bound to a path of it (§2.6).
    static func trackedNames(in body: CodeBlockSyntax, root: String) -> Set<String> {
        var names: Set<String> = [root]
        final class Binder: SyntaxVisitor {
            var loops: [ForStmtSyntax] = []
            var lets: [PatternBindingSyntax] = []
            override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind { loops.append(node); return .visitChildren }
            override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind { lets.append(node); return .visitChildren }
        }
        let binder = Binder(viewMode: .sourceAccurate)
        binder.walk(body)
        var changed = true
        while changed {
            changed = false
            for loop in binder.loops where isPath(loop.sequence, names) {
                if let ident = loop.pattern.as(IdentifierPatternSyntax.self), names.insert(ident.identifier.text).inserted {
                    changed = true
                }
            }
            for binding in binder.lets {
                if let ident = binding.pattern.as(IdentifierPatternSyntax.self), let value = binding.initializer?.value,
                   isPath(value, names), names.insert(ident.identifier.text).inserted {
                    changed = true
                }
            }
        }
        return names
    }

    /// A member chain (no calls) rooted at one of `names`.
    static func isPath(_ expr: ExprSyntax, _ names: Set<String>) -> Bool {
        var current = expr
        while let member = current.as(MemberAccessExprSyntax.self) {
            guard let base = member.base else { return false }
            current = base
        }
        if let ref = current.as(DeclReferenceExprSyntax.self) { return names.contains(ref.baseName.text) }
        return false
    }

    static func piece(_ expr: ExprSyntax, _ names: Set<String>) -> Piece {
        // §2.6: `q`, a path of `q`, or a member-access transform of either; never a call on it (a call may map
        // its argument to a fixed word, as `stereotypeLabel(for:)` does).
        if isPath(expr, names) { return .element(expr.trimmedDescription) }
        return .cut(expr.trimmedDescription)
    }

    static func pieces(_ expr: ExprSyntax, _ names: Set<String>) -> [Piece] {
        if let literal = expr.as(StringLiteralExprSyntax.self) {
            return literal.segments.compactMap { segment in
                if let text = segment.as(StringSegmentSyntax.self) { return .literal(text.content.text) }
                if let interp = segment.as(ExpressionSegmentSyntax.self), let inner = interp.expressions.first?.expression {
                    return piece(inner, names)
                }
                return nil
            }
        }
        if let infix = expr.as(InfixOperatorExprSyntax.self),
           infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "+" {
            return pieces(infix.leftOperand, names) + pieces(infix.rightOperand, names)
        }
        if let tuple = expr.as(TupleExprSyntax.self), tuple.elements.count == 1 {
            return pieces(tuple.elements.first!.expression, names)
        }
        return [piece(expr, names)]
    }

    static func transform(of template: String, _ names: Set<String>) -> String? {
        // `⟨text.xmlEscaped⟩`: a member beyond a tracked name is recorded as a transform.
        let regex = /⟨([A-Za-z_][A-Za-z0-9_]*)((?:\.[A-Za-z_][A-Za-z0-9_]*)+)⟩/
        for match in template.matches(of: regex) where names.contains(String(match.1)) {
            return String(match.2)
        }
        return nil
    }

    /// A string-building site whose pieces put a tracked name next to non-whitespace literal text.
    static func writeSite(in body: CodeBlockSyntax, names: Set<String>) -> (String, String?)? {
        var candidates: [[Piece]] = []
        // String literals and top-most `+` chains.
        final class Sites: SyntaxVisitor {
            var literals: [StringLiteralExprSyntax] = []
            var chains: [InfixOperatorExprSyntax] = []
            var lists: [CodeBlockItemListSyntax] = []
            override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
                let isPlus = node.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "+"
                let parentIsPlus = node.parent?.as(InfixOperatorExprSyntax.self)?
                    .operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "+"
                if isPlus, !parentIsPlus { chains.append(node) }
                return .visitChildren
            }
            override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
                literals.append(node)
                return .visitChildren
            }
            override func visit(_ node: CodeBlockItemListSyntax) -> SyntaxVisitorContinueKind {
                lists.append(node)
                return .visitChildren
            }
        }
        let sites = Sites(viewMode: .sourceAccurate)
        sites.walk(body)
        for literal in sites.literals { candidates.append(pieces(ExprSyntax(literal), names)) }
        for chain in sites.chains { candidates.append(pieces(ExprSyntax(chain), names)) }
        // Runs of consecutive `var v = …` / `v = …` / `v += …` statements on one local.
        for list in sites.lists {
            var current: (String, [Piece])?
            for item in list {
                if let (variable, value) = assignment(item.item), current == nil || current!.0 == variable {
                    current = (variable, (current?.1 ?? []) + pieces(value, names))
                } else {
                    if let run = current { candidates.append(run.1) }
                    current = assignment(item.item).map { ($0.0, pieces($0.1, names)) }
                }
            }
            if let run = current { candidates.append(run.1) }
        }
        for candidate in candidates {
            let (template, hasElement, _, distinctive) = BodyWalker.run(candidate)
            if hasElement, distinctive, let template { return (template, transform(of: template, names)) }
        }
        return nil
    }

    static func assignment(_ item: CodeBlockItemSyntax.Item) -> (String, ExprSyntax)? {
        if let decl = item.as(VariableDeclSyntax.self), decl.bindings.count == 1, let binding = decl.bindings.first,
           let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
           let value = binding.initializer?.value {
            return (name, value)
        }
        let expr = item.as(ExprSyntax.self) ?? item.as(ExpressionStmtSyntax.self)?.expression
        if let infix = expr?.as(InfixOperatorExprSyntax.self), let target = infix.leftOperand.as(DeclReferenceExprSyntax.self) {
            let op = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text
            if op == "+=" || infix.operator.is(AssignmentExprSyntax.self) { return (target.baseName.text, infix.rightOperand) }
        }
        return nil
    }
}

/// Every call in a body, outside nested closures and functions.
final class CallCollector: SyntaxVisitor {
    var calls: [FunctionCallExprSyntax] = []
    static func collect(_ body: CodeBlockSyntax) -> [FunctionCallExprSyntax] {
        let collector = CallCollector(viewMode: .sourceAccurate)
        collector.walk(body)
        return collector.calls
    }
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind { calls.append(node); return .visitChildren }
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
}

/// Whether a node reads any of `names` (a member name `x.name` is not a read of `name`).
final class NameReadFinder: SyntaxVisitor {
    let names: Set<String>
    var found = false
    init(_ names: Set<String>) { self.names = names; super.init(viewMode: .sourceAccurate) }
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        if names.contains(node.baseName.text),
           !(node.parent?.as(MemberAccessExprSyntax.self).map { $0.declName.id == node.id } ?? false) {
            found = true
        }
        return .skipChildren
    }

    static func reads(_ node: Syntax, _ names: Set<String>) -> Bool {
        guard !names.isEmpty else { return false }
        let finder = NameReadFinder(names)
        finder.walk(node)
        return finder.found
    }
}
