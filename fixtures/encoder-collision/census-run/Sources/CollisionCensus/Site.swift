import SwiftSyntax

/// One literal (b) found, with where it landed (§2.5).
struct SiteRow: Codable {
    let key: String
    let repository: String
    let file: String
    let line: Int
    let owner: String
    let ownerType: String?
    let loopVariable: String
    let name: String
    let idExpression: String
    let callee: String
    let literal: String
    let buffer: String?
    /// `admitted`, `recall: chain, no witness`, `recall: not a chain`, `skipped: …`, `refused: ambiguous`,
    /// `refused: no returned buffer`.
    let filing: String
    let resolvedFile: String?
    let resolvedLine: Int?
    let resolvedType: String?
    let steps: [ReplacementChainClassifier.Step]?
    let witness: Witness?
    let identifierWitnesses: [Witness]
    let ambiguousWith: [String]
}

/// Nodes of one kind below `root`, not descending into nested functions or closures (the root itself may be one).
final class Collect<Node: SyntaxProtocol>: SyntaxAnyVisitor {
    var found: [Node] = []
    let root: SyntaxIdentifier
    let intoClosures: Bool

    init(_ root: some SyntaxProtocol, intoClosures: Bool = false) {
        self.root = root.id
        self.intoClosures = intoClosures
        super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        if node.id != root, !intoClosures, node.is(ClosureExprSyntax.self) || node.is(FunctionDeclSyntax.self) {
            return .skipChildren
        }
        if let match = node.as(Node.self) { found.append(match) }
        return .visitChildren
    }

    static func all(in root: some SyntaxProtocol, intoClosures: Bool = false) -> [Node] {
        let visitor = Collect<Node>(root, intoClosures: intoClosures)
        visitor.walk(root)
        return visitor.found
    }
}

/// The function-like body a loop sits in.
struct Owner {
    let node: Syntax
    let name: String

    static func of(_ loop: ForStmtSyntax) -> Owner? {
        var current = loop.parent
        while let node = current {
            if let decl = node.as(FunctionDeclSyntax.self) { return Owner(node: node, name: decl.name.text) }
            if node.is(InitializerDeclSyntax.self) { return Owner(node: node, name: "init") }
            if node.is(ClosureExprSyntax.self) { return Owner(node: node, name: "closure") }
            if node.is(AccessorDeclSyntax.self) || node.is(AccessorBlockSyntax.self) {
                var up = node.parent
                while let candidate = up, !candidate.is(PatternBindingSyntax.self) { up = candidate.parent }
                let name = up?.as(PatternBindingSyntax.self)?.pattern.trimmedDescription ?? "accessor"
                return Owner(node: node, name: name)
            }
            current = node.parent
        }
        return nil
    }
}

/// An id expression (§2.1): `F(n)`, `Self.F(n)`, `T.F(n)`, `self.F(n)` or `n.F`.
struct IdExpression {
    let callee: String
    let qualifier: String?
    let member: Bool
    let path: String
    let text: String
}

enum SiteReader {
    /// A member chain with no calls, rooted at `element`.
    static func path(_ expr: ExprSyntax, element: String) -> String? {
        var current = expr
        while let member = current.as(MemberAccessExprSyntax.self) {
            guard let base = member.base else { return nil }
            current = base
        }
        guard current.as(DeclReferenceExprSyntax.self)?.baseName.text == element else { return nil }
        return expr.trimmedDescription
    }

    static func interpolations(_ literal: StringLiteralExprSyntax) -> [ExprSyntax] {
        literal.segments.compactMap { $0.as(ExpressionSegmentSyntax.self)?.expressions.first?.expression }
    }

    static func idOf(_ expr: ExprSyntax, element: String, index: CandidateIndex) -> IdExpression? {
        if let call = expr.as(FunctionCallExprSyntax.self), call.arguments.count == 1, call.trailingClosure == nil,
           let argument = call.arguments.first, let p = path(argument.expression, element: element) {
            if let ref = call.calledExpression.as(DeclReferenceExprSyntax.self) {
                return IdExpression(callee: ref.baseName.text, qualifier: nil, member: false, path: p,
                                    text: expr.trimmedDescription)
            }
            if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
               let base = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text {
                let callee = member.declName.baseName.text
                if base == "Self" || base == "self" {
                    return IdExpression(callee: callee, qualifier: nil, member: false, path: p, text: expr.trimmedDescription)
                }
                if base != element, base.first?.isUppercase == true {
                    return IdExpression(callee: callee, qualifier: base, member: false, path: p, text: expr.trimmedDescription)
                }
            }
            return nil
        }
        if let member = expr.as(MemberAccessExprSyntax.self), let base = member.base,
           let p = path(base, element: element),
           case .candidate = index.resolve(member.declName.baseName.text, enclosingType: nil, qualifier: nil, member: true) {
            return IdExpression(callee: member.declName.baseName.text, qualifier: nil, member: true, path: p,
                                text: expr.trimmedDescription)
        }
        return nil
    }

    /// The buffer a node is appended to: `X.append(node)`, `X.append(contentsOf: [node])`, `X += node`,
    /// `X += [node]`.
    static func appendTarget(_ node: ExprSyntax) -> String? {
        var expr = Syntax(node)
        if let element = expr.parent?.as(ArrayElementSyntax.self), let array = element.parent?.parent?.as(ArrayExprSyntax.self) {
            expr = Syntax(array)
        }
        if let labeled = expr.parent?.as(LabeledExprSyntax.self),
           let call = labeled.parent?.parent?.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "append",
           let buffer = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text {
            return buffer
        }
        if let infix = expr.parent?.as(InfixOperatorExprSyntax.self), infix.rightOperand.id == expr.id,
           infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "+=",
           let buffer = infix.leftOperand.as(DeclReferenceExprSyntax.self)?.baseName.text {
            return buffer
        }
        return nil
    }

    static func isDescendant(_ node: Syntax, of ancestor: Syntax) -> Bool {
        var current: Syntax? = node
        while let candidate = current {
            if candidate.id == ancestor.id { return true }
            current = candidate.parent
        }
        return false
    }

    /// §2.2: `buf` is a `var` of the owner outside the loop, and the owner returns it.
    static func returnsBuffer(_ buffer: String, owner: Owner, loop: ForStmtSyntax) -> Bool {
        let declared = Collect<VariableDeclSyntax>.all(in: owner.node).contains { decl in
            decl.bindingSpecifier.tokenKind == .keyword(.var) && !isDescendant(Syntax(decl), of: Syntax(loop))
                && decl.bindings.contains { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == buffer }
        }
        guard declared else { return false }
        func isBuffer(_ expr: ExprSyntax) -> Bool {
            if expr.as(DeclReferenceExprSyntax.self)?.baseName.text == buffer { return true }
            if let call = expr.as(FunctionCallExprSyntax.self), let member = call.calledExpression.as(MemberAccessExprSyntax.self),
               member.declName.baseName.text == "joined",
               member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == buffer { return true }
            return false
        }
        return Collect<ReturnStmtSyntax>.all(in: owner.node).contains { ret in
            guard let expr = ret.expression else { return false }
            if isBuffer(expr) { return true }
            if let infix = expr.as(InfixOperatorExprSyntax.self),
               infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "+",
               isBuffer(infix.leftOperand), infix.rightOperand.is(StringLiteralExprSyntax.self) { return true }
            return false
        }
    }

    /// §2.4: the id, or a binding of it, used as a key, a set member or an `==` operand anywhere in the owner.
    static func skipReason(id: IdExpression, bindings: [String], owner: Owner, loop: ForStmtSyntax) -> String? {
        var uses: [Syntax] = Collect<FunctionCallExprSyntax>.all(in: owner.node, intoClosures: true)
            .filter { $0.trimmedDescription == id.text }.map(Syntax.init)
        uses += Collect<MemberAccessExprSyntax>.all(in: owner.node, intoClosures: true)
            .filter { id.member && $0.trimmedDescription == id.text }.map(Syntax.init)
        uses += Collect<DeclReferenceExprSyntax>.all(in: loop.body, intoClosures: true)
            .filter { bindings.contains($0.baseName.text) }.map(Syntax.init)
        for use in uses {
            var node = use
            if let element = node.parent?.as(ArrayElementSyntax.self), let array = element.parent?.parent?.as(ArrayExprSyntax.self) {
                node = Syntax(array)
            }
            if let labeled = node.parent?.as(LabeledExprSyntax.self), let list = labeled.parent {
                if list.parent?.is(SubscriptCallExprSyntax.self) == true { return "dictionary key" }
                if let call = list.parent?.as(FunctionCallExprSyntax.self) {
                    let name = call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
                        ?? call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
                    if ["insert", "contains", "remove"].contains(name) { return "set member (\(name!))" }
                    if name == "Set" { return "set element" }
                }
            }
            if let infix = node.parent?.as(InfixOperatorExprSyntax.self),
               ["==", "!="].contains(infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text) {
                return "compared"
            }
        }
        return nil
    }

    static func read(_ file: Census.Parsed, repository: String, index: CandidateIndex, into rows: inout [SiteRow],
                     tally: inout [String: Int]) {
        var filed: Set<SyntaxIdentifier> = []
        for loop in file.loops {
            guard let element = loop.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let owner = Owner.of(loop) else { continue }
            let body = loop.body
            // Local bindings of the loop body and every assignment to them.
            var assignments: [String: [ExprSyntax]] = [:]
            var initialisers: [String: ExprSyntax] = [:]
            for decl in Collect<VariableDeclSyntax>.all(in: body) {
                for binding in decl.bindings {
                    guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
                    assignments[name] = binding.initializer.map { [$0.value] } ?? []
                    if let value = binding.initializer?.value { initialisers[name] = value }
                }
            }
            for infix in Collect<InfixOperatorExprSyntax>.all(in: body) {
                guard let target = infix.leftOperand.as(DeclReferenceExprSyntax.self)?.baseName.text,
                      assignments[target] != nil else { continue }
                if infix.operator.is(AssignmentExprSyntax.self)
                    || infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "+=" {
                    assignments[target, default: []].append(infix.rightOperand)
                    initialisers[target] = nil
                }
            }
            // Bindings of a name: every assignment is the name, or a literal interpolating it.
            var nameBindings: [String: Set<String>] = [:]
            func names(in expr: ExprSyntax) -> Set<String> {
                if let p = path(expr, element: element) { return [p] }
                if let ref = expr.as(DeclReferenceExprSyntax.self), let bound = nameBindings[ref.baseName.text] { return bound }
                return []
            }
            for _ in 0..<3 {
                for (binding, values) in assignments where !values.isEmpty {
                    var common: Set<String>?
                    for value in values {
                        var here = names(in: value)
                        if let literal = value.as(StringLiteralExprSyntax.self) {
                            here = interpolations(literal).reduce(into: Set<String>()) { $0.formUnion(names(in: $1)) }
                        }
                        common = common.map { $0.intersection(here) } ?? here
                    }
                    if let common, !common.isEmpty { nameBindings[binding] = common } else { nameBindings[binding] = nil }
                }
            }
            // Bindings of an id: a binding whose only assignment is its initializer, an id expression.
            var idBindings: [String: IdExpression] = [:]
            for (binding, value) in initialisers where assignments[binding]?.count == 1 {
                if let id = idOf(value, element: element, index: index) { idBindings[binding] = id }
            }
            for literal in Collect<StringLiteralExprSyntax>.all(in: body) where !filed.contains(literal.id) {
                let parts = interpolations(literal)
                var present = Set<String>()
                var ids: [(IdExpression, [String])] = []
                for part in parts {
                    present.formUnion(names(in: part))
                    if let id = idOf(part, element: element, index: index) { ids.append((id, [])) }
                    if let ref = part.as(DeclReferenceExprSyntax.self), let id = idBindings[ref.baseName.text] {
                        ids.append((id, [ref.baseName.text]))
                    }
                }
                guard let (id, bound) = ids.first(where: { present.contains($0.0.path) }) else { continue }
                filed.insert(literal.id)
                let resolution = index.resolve(id.callee, enclosingType: TypeContext.enclosingType(Syntax(loop)),
                                               qualifier: id.qualifier, member: id.member)
                let candidate: Candidate?
                var ambiguous: [String] = []
                switch resolution {
                case .none(let reason):
                    tally["not a site: \(reason)", default: 0] += 1
                    continue
                case .ambiguous(let all):
                    candidate = nil
                    ambiguous = all.map { "\($0.file):\($0.line)" }
                case .candidate(let found):
                    candidate = found
                }
                // §2.2: the literal, or a loop-local `let` it initialises, is appended to a returned buffer.
                var buffer = appendTarget(ExprSyntax(literal))
                if buffer == nil, let binding = literal.parent?.as(InitializerClauseSyntax.self)?.parent?.as(PatternBindingSyntax.self),
                   let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                    buffer = Collect<DeclReferenceExprSyntax>.all(in: body).filter { $0.baseName.text == name }
                        .lazy.compactMap { appendTarget(ExprSyntax($0)) }.first
                }
                let returned = buffer.map { returnsBuffer($0, owner: owner, loop: loop) } ?? false
                var filing: String
                if !returned {
                    filing = "refused: no returned buffer"
                } else if !ambiguous.isEmpty {
                    filing = "refused: ambiguous"
                } else if let reason = skipReason(id: id, bindings: bound, owner: owner, loop: loop) {
                    filing = "skipped: \(reason)"
                } else if let candidate, candidate.isChain {
                    filing = candidate.witness == nil ? "recall: chain, no witness" : "admitted"
                } else {
                    filing = "recall: not a chain"
                }
                let line = file.converter.location(for: literal.positionAfterSkippingLeadingTrivia).line
                rows.append(SiteRow(
                    key: "\(repository):\(file.relative):\(line)", repository: repository, file: file.relative,
                    line: line, owner: owner.name, ownerType: TypeContext.enclosingType(owner.node),
                    loopVariable: element, name: id.path, idExpression: id.text, callee: id.callee,
                    literal: literal.trimmedDescription, buffer: buffer, filing: filing,
                    resolvedFile: candidate?.file, resolvedLine: candidate?.line, resolvedType: candidate?.typeName,
                    steps: candidate?.steps, witness: candidate?.witness,
                    identifierWitnesses: candidate?.identifierWitnesses ?? [], ambiguousWith: ambiguous))
            }
        }
    }
}
