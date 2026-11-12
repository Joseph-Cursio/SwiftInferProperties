import SwiftSyntax

/// Recall probe, added after the first report (write-up, "Recorded after the first report"): every string literal
/// anywhere that interpolates `G(A)` (or a `let` bound to it in the same block) beside `A` itself, where `G`
/// resolves to a repository candidate. It records the context (b) would need, so a zero from (b) can be told from
/// blindness. It never enters the decision.
struct ProbeRow: Codable {
    let key: String
    let repository: String
    let file: String
    let line: Int
    let owner: String?
    let ownerType: String?
    let argument: String
    let callee: String
    let literal: String
    let resolvedTo: String?
    let chain: Bool
    let witness: Witness?
    /// `for-identifier`, `for-tuple`, `for-other`, `closure`, `none`: the innermost loop or closure around it.
    let context: String
    let contextDetail: String?
    let siteFiling: String?
}

enum Probe {
    static func context(_ node: Syntax) -> (String, String?) {
        var current = node.parent
        while let candidate = current {
            if let loop = candidate.as(ForStmtSyntax.self) {
                if loop.pattern.is(IdentifierPatternSyntax.self) { return ("for-identifier", loop.pattern.trimmedDescription) }
                if loop.pattern.is(TuplePatternSyntax.self) { return ("for-tuple", loop.pattern.trimmedDescription) }
                return ("for-other", loop.pattern.trimmedDescription)
            }
            if let closure = candidate.as(ClosureExprSyntax.self) {
                var call = closure.parent
                while let up = call, !up.is(FunctionCallExprSyntax.self), !up.is(CodeBlockItemSyntax.self) { call = up.parent }
                let name = call?.as(FunctionCallExprSyntax.self)?.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
                return ("closure", name)
            }
            if candidate.is(FunctionDeclSyntax.self) || candidate.is(InitializerDeclSyntax.self)
                || candidate.is(AccessorDeclSyntax.self) { return ("none", nil) }
            current = candidate.parent
        }
        return ("none", nil)
    }

    static func callOf(_ expr: ExprSyntax) -> (String, String?, ExprSyntax)? {
        guard let call = expr.as(FunctionCallExprSyntax.self), call.arguments.count == 1, call.trailingClosure == nil,
              let argument = call.arguments.first?.expression else { return nil }
        if let ref = call.calledExpression.as(DeclReferenceExprSyntax.self) { return (ref.baseName.text, nil, argument) }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           let base = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
           base == "Self" || base == "self" || base.first?.isUppercase == true {
            return (member.declName.baseName.text, base == "Self" || base == "self" ? nil : base, argument)
        }
        return nil
    }

    static func read(_ file: Census.Parsed, repository: String, index: CandidateIndex, sites: [SiteRow],
                     into rows: inout [ProbeRow]) {
        let filings = Dictionary(sites.filter { $0.repository == repository && $0.file == file.relative }
            .map { ($0.line, $0.filing) }, uniquingKeysWith: { first, _ in first })
        for literal in Collect<StringLiteralExprSyntax>.all(in: file.tree, intoClosures: true) {
            let parts = SiteReader.interpolations(literal)
            let texts = Set(parts.map(\.trimmedDescription))
            // `let x = G(A)` in the block that holds the literal's statement.
            var bound: [String: ExprSyntax] = [:]
            var block = literal.parent
            while let up = block, !up.is(CodeBlockItemListSyntax.self) { block = up.parent }
            if let list = block {
                for decl in Collect<VariableDeclSyntax>.all(in: list) {
                    for binding in decl.bindings {
                        if let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                           let value = binding.initializer?.value { bound[name] = value }
                    }
                }
            }
            for part in parts {
                let expr = part.as(DeclReferenceExprSyntax.self).flatMap { bound[$0.baseName.text] } ?? part
                guard let (callee, qualifier, argument) = callOf(expr) else { continue }
                let argumentText = argument.trimmedDescription
                guard texts.contains(argumentText) || parts.contains(where: {
                    $0.as(DeclReferenceExprSyntax.self).flatMap { bound[$0.baseName.text] }?.trimmedDescription == argumentText
                }) else { continue }
                let resolution = index.resolve(callee, enclosingType: TypeContext.enclosingType(Syntax(literal)),
                                               qualifier: qualifier, member: false)
                guard case .candidate(let found) = resolution else { continue }
                let line = file.converter.location(for: literal.positionAfterSkippingLeadingTrivia).line
                let (where_, detail) = context(Syntax(literal))
                var owner: Syntax? = Syntax(literal)
                var ownerName: String?
                while let up = owner?.parent {
                    if let decl = up.as(FunctionDeclSyntax.self) { ownerName = decl.name.text; break }
                    if up.is(InitializerDeclSyntax.self) { ownerName = "init"; break }
                    owner = up
                }
                rows.append(ProbeRow(
                    key: "\(repository):\(file.relative):\(line)", repository: repository, file: file.relative, line: line,
                    owner: ownerName, ownerType: TypeContext.enclosingType(Syntax(literal)), argument: argumentText,
                    callee: callee, literal: literal.trimmedDescription, resolvedTo: "\(found.file):\(found.line)",
                    chain: found.isChain, witness: found.witness, context: where_, contextDetail: detail,
                    siteFiling: filings[line]))
                break
            }
        }
    }
}

/// Every use of a colliding chain (a call `F(…)` / `T.F(…)` / `Self.F(…)`, or a member `x.F` for a getter) that
/// resolves to it, with its statement, for the hand-read recall check.
struct UseRow: Codable {
    let key: String
    let repository: String
    let file: String
    let line: Int
    let chain: String
    let chainAt: String
    let owner: String?
    let statement: String
    let context: String
    let contextDetail: String?
}

extension Probe {
    static func uses(_ file: Census.Parsed, repository: String, index: CandidateIndex, into rows: inout [UseRow]) {
        func record(_ node: Syntax, _ found: Candidate) {
            guard found.witness != nil else { return }
            var statement: Syntax = node
            while let up = statement.parent, !up.is(CodeBlockItemSyntax.self), !up.is(MemberBlockItemSyntax.self) { statement = up }
            var owner: String?
            var up = node.parent
            while let candidate = up {
                if let decl = candidate.as(FunctionDeclSyntax.self) { owner = decl.name.text; break }
                if let binding = candidate.as(PatternBindingSyntax.self) { owner = binding.pattern.trimmedDescription; break }
                if candidate.is(InitializerDeclSyntax.self) { owner = "init"; break }
                up = candidate.parent
            }
            let line = file.converter.location(for: node.positionAfterSkippingLeadingTrivia).line
            let (where_, detail) = context(node)
            rows.append(UseRow(key: "\(repository):\(file.relative):\(line)", repository: repository, file: file.relative,
                               line: line, chain: "\(found.typeName ?? "-").\(found.name)", chainAt: "\(found.file):\(found.line)",
                               owner: owner, statement: String(statement.trimmedDescription.prefix(400)),
                               context: where_, contextDetail: detail))
        }
        for call in Collect<FunctionCallExprSyntax>.all(in: file.tree, intoClosures: true) {
            guard let (callee, qualifier, _) = callOf(ExprSyntax(call)) else { continue }
            if case .candidate(let found) = index.resolve(callee, enclosingType: TypeContext.enclosingType(Syntax(call)),
                                                          qualifier: qualifier, member: false) { record(Syntax(call), found) }
        }
        for member in Collect<MemberAccessExprSyntax>.all(in: file.tree, intoClosures: true) where member.base != nil {
            guard member.parent?.as(FunctionCallExprSyntax.self)?.calledExpression.id != member.id else { continue }
            if case .candidate(let found) = index.resolve(member.declName.baseName.text, enclosingType: nil,
                                                          qualifier: nil, member: true) { record(Syntax(member), found) }
        }
    }
}
