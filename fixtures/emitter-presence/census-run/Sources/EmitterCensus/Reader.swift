import Foundation
import SwiftOperators
import SwiftSyntax

// The reader `R` of `docs/plans/emitter-presence-census-scope.md` §2. A prototype: if the decision is BUILD, the
// shipped reader is written from the scope, not from this file.

/// What a helper hop found (§2.6).
struct HelperRead: Codable {
    var chain: [String] = []
    var resolved = false
    var reason: String?
    var transform: String?
    var template: String?
}

/// One accumulation inside a qualifying (or W1) loop that reads a tracked name (§2.4).
struct Obligation: Codable {
    var line: Int
    var kind: String
    var statement: String
    var template: String?
    var guards: [String]
    var depth: Int
    var sources: [String]
    var encoders: [String]
    var helper: HelperRead?
    var widened: Bool

    /// §2.7: primary, segment, or a resolved helper, from a non-widened loop.
    var statable: Bool {
        !widened && (kind == "primary" || kind == "segment" || (kind == "helper" && helper?.resolved == true))
    }
}

struct Reading: Codable {
    var returnType: String
    var accumulator: String?
    var obligations: [Obligation] = []
    var loops: [String] = []
    var widenings: [String] = []
    var refusal: String?
    var tier: String?
    var hops: Int = 0

    var admitted: Bool { refusal == nil && tier != nil }
}

/// A function declaration a helper hop can resolve to (§2.6).
struct IndexedFunction {
    let decl: FunctionDeclSyntax
    let file: String
}

/// Every function in one repository, keyed by base name.
struct FunctionIndex {
    var byName: [String: [IndexedFunction]] = [:]

    mutating func add(_ decl: FunctionDeclSyntax, file: String) {
        byName[decl.name.text, default: []].append(IndexedFunction(decl: decl, file: file))
    }

    /// The unique declaration a call resolves to: same base name, and the call's labels match the parameters in
    /// order, skipping parameters with a default value.
    func resolve(_ call: FunctionCallExprSyntax) -> (IndexedFunction?, String?) {
        guard let name = Reader.calleeName(call) else { return (nil, "callee not a name") }
        let labels = call.arguments.map { $0.label?.text ?? "_" }
        let matches = (byName[name] ?? []).filter { Self.labelsMatch(labels, $0.decl) }
        if matches.isEmpty { return (nil, "no declaration of \(name)") }
        if matches.count > 1 { return (nil, "\(matches.count) declarations of \(name)") }
        return (matches[0], nil)
    }

    static func labelsMatch(_ labels: [String], _ decl: FunctionDeclSyntax) -> Bool {
        var remaining = labels[...]
        for parameter in decl.signature.parameterClause.parameters {
            let label = parameter.firstName.text
            if let next = remaining.first, next == label {
                remaining = remaining.dropFirst()
            } else if parameter.defaultValue == nil {
                return false
            }
        }
        return remaining.isEmpty
    }

    /// The parameter an argument at `index` binds, by the same walk as `labelsMatch`.
    static func parameterName(for index: Int, in call: FunctionCallExprSyntax, _ decl: FunctionDeclSyntax) -> String? {
        let labels = call.arguments.map { $0.label?.text ?? "_" }
        var position = 0
        for parameter in decl.signature.parameterClause.parameters {
            guard position < labels.count else { return nil }
            if labels[position] == parameter.firstName.text {
                if position == index { return (parameter.secondName ?? parameter.firstName).text }
                position += 1
            }
        }
        return nil
    }
}

enum Piece {
    case literal(String)
    case element(String)
    case cut(String)
    case helper(FunctionCallExprSyntax)
}

enum Reader {
    static let stringReturns: Set<String> = ["String", "Swift.String"]
    static let arrayReturns: Set<String> = ["[String]", "Array<String>", "[Swift.String]"]
    static let characterNames: Set<String> = ["c", "ch", "char", "character", "scalar"]
    static let stringViews: Set<String> = ["unicodeScalars", "utf8", "utf16", "characters"]
    static let widenOps: Set<String> = ["sorted", "enumerated", "filter"]

    // MARK: Shape (§2.1)

    /// nil when the shape passes; W2 passes here and is flagged by `read`.
    static func shapeRefusal(_ function: FunctionDeclSyntax) -> String? {
        guard function.body != nil else { return "shape" }
        let returned = function.signature.returnClause?.type.trimmedDescription ?? ""
        let allowed = stringReturns.contains(returned) || arrayReturns.contains(returned) || returned == "String?"
        if !allowed { return "shape" }
        if function.signature.effectSpecifiers?.asyncSpecifier != nil { return "shape" }
        if function.modifiers.contains(where: { $0.name.tokenKind == .keyword(.mutating) }) { return "shape" }
        return nil
    }

    static func calleeName(_ call: FunctionCallExprSyntax) -> String? {
        if let ref = call.calledExpression.as(DeclReferenceExprSyntax.self) { return ref.baseName.text }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) { return member.declName.baseName.text }
        return nil
    }

    // MARK: Reading a function

    static func read(_ function: FunctionDeclSyntax, index: FunctionIndex, converter: SourceLocationConverter) -> Reading {
        let returned = function.signature.returnClause?.type.trimmedDescription ?? ""
        var reading = Reading(returnType: returned)
        if returned == "String?" { reading.widenings.append("W2") }
        guard let rawBody = function.body else { reading.refusal = "shape"; return reading }
        let folded = OperatorTable.standardOperators.foldAll(rawBody) { _ in }
        guard let body = folded.as(CodeBlockSyntax.self) else { reading.refusal = "shape"; return reading }

        let parameters = function.signature.parameterClause.parameters.map { ($0.secondName ?? $0.firstName).text }
        let parameterTypes = Dictionary(
            function.signature.parameterClause.parameters.map {
                (($0.secondName ?? $0.firstName).text, $0.type.trimmedDescription)
            }
        ) { first, _ in first }
        let isInstance = Self.isInstanceMethod(function)

        // §2.2: the accumulator.
        let returns = ReturnCollector.collect(body)
        var accumulator: String?
        for ret in returns {
            guard let expr = ret.expression else { reading.refusal = "return: other"; return reading }
            if let name = accumulatorName(in: expr) {
                if accumulator == nil { accumulator = name } else if accumulator != name {
                    reading.refusal = "return: other"; return reading
                }
            } else if !isLiteralReturn(expr) {
                reading.refusal = "return: other"; return reading
            }
        }
        if returns.isEmpty, let last = body.statements.last?.item.as(ExprSyntax.self) {
            accumulator = accumulatorName(in: last)
            if accumulator == nil { reading.refusal = "accumulator: none"; return reading }
        }
        guard let acc = accumulator else { reading.refusal = "accumulator: none"; return reading }
        reading.accumulator = acc
        guard declaresAccumulator(acc, in: body) else { reading.refusal = "accumulator: other"; return reading }

        // Locals declared at the top level (never parameter paths).
        var topLocals: Set<String> = []
        for item in body.statements {
            if let decl = item.item.as(VariableDeclSyntax.self) {
                for binding in decl.bindings {
                    if let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                        topLocals.insert(name)
                    }
                }
            }
        }
        var walker = BodyWalker(
            accumulator: acc, parameters: Set(parameters), parameterTypes: parameterTypes,
            isInstance: isInstance, topLocals: topLocals, index: index, converter: converter
        )
        walker.walkTop(body.statements)
        if let refusal = walker.rowRefusal { reading.refusal = refusal }
        reading.obligations = walker.obligations
        reading.loops = walker.loops
        if walker.sawW1 { reading.widenings.append("W1") }
        if walker.obligations.contains(where: { $0.kind == "W3" }) { reading.widenings.append("W3") }
        if reading.refusal == nil, let tail = walker.postLoopRefusal { reading.refusal = tail }
        // Sensitivity run (recorded after the first report, not part of the frozen run): §2.5's tail rule applied to
        // every accumulator statement after the top-level statement holding the last obligation, nested ones
        // included. The frozen run looked only at top-level statements, so it missed appends inside a later `if`,
        // `for` or `switch`.
        if reading.refusal == nil, ProcessInfo.processInfo.environment["EMITTER_STRICT_TAIL"] == "1",
           let lastLine = walker.obligations.map(\.line).max() {
            let items = Array(body.statements)
            if let holder = items.lastIndex(where: {
                converter.location(for: $0.positionAfterSkippingLeadingTrivia).line <= lastLine
            }) {
                final class Items: SyntaxVisitor {
                    var found: [CodeBlockItemSyntax] = []
                    override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
                        found.append(node); return .visitChildren
                    }
                    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
                }
                for item in items[(holder + 1)...] {
                    let finder = Items(viewMode: .sourceAccurate)
                    finder.walk(item)
                    if let refusal = finder.found.lazy.compactMap({ walker.tailMutation($0) }).first {
                        reading.refusal = "strict \(refusal)"
                        break
                    }
                }
            }
        }
        if reading.refusal == nil {
            let statable = walker.obligations.filter(\.statable)
            if statable.isEmpty {
                reading.refusal = walker.obligations.isEmpty ? "no obligation" : "no statable obligation"
            } else if reading.widenings.contains("W2") {
                reading.refusal = "W2"
            } else {
                reading.tier = statable.contains { $0.kind == "helper" } ? "helper" : "as-written"
                reading.hops = statable.compactMap { $0.helper?.chain.count }.max() ?? 0
            }
        }
        return reading
    }

    static func isInstanceMethod(_ function: FunctionDeclSyntax) -> Bool {
        let isStatic = function.modifiers.contains { [.keyword(.static), .keyword(.class)].contains($0.name.tokenKind) }
        if isStatic { return false }
        var node = function.parent
        while let current = node {
            if current.is(StructDeclSyntax.self) || current.is(ClassDeclSyntax.self) || current.is(EnumDeclSyntax.self)
                || current.is(ActorDeclSyntax.self) || current.is(ExtensionDeclSyntax.self)
                || current.is(ProtocolDeclSyntax.self) { return true }
            if current.is(FunctionDeclSyntax.self) || current.is(ClosureExprSyntax.self) { return false }
            node = current.parent
        }
        return false
    }

    /// `acc`, `acc.joined()`, `acc.joined(separator: LIT)`, each optionally `+ LIT`.
    static func accumulatorName(in expr: ExprSyntax) -> String? {
        var expr = expr
        if let infix = expr.as(InfixOperatorExprSyntax.self),
           infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "+",
           infix.rightOperand.is(StringLiteralExprSyntax.self) {
            expr = infix.leftOperand
        }
        if let ref = expr.as(DeclReferenceExprSyntax.self) { return ref.baseName.text }
        if let call = expr.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "joined",
           let base = member.base?.as(DeclReferenceExprSyntax.self) {
            let args = Array(call.arguments)
            if args.isEmpty { return base.baseName.text }
            if args.count == 1, args[0].label?.text == "separator", args[0].expression.is(StringLiteralExprSyntax.self) {
                return base.baseName.text
            }
        }
        return nil
    }

    static func isLiteralReturn(_ expr: ExprSyntax) -> Bool {
        if expr.is(StringLiteralExprSyntax.self) || expr.is(NilLiteralExprSyntax.self) { return true }
        if let array = expr.as(ArrayExprSyntax.self) {
            return array.elements.allSatisfy { $0.expression.is(StringLiteralExprSyntax.self) }
        }
        return false
    }

    static func declaresAccumulator(_ name: String, in body: CodeBlockSyntax) -> Bool {
        for item in body.statements {
            guard let decl = item.item.as(VariableDeclSyntax.self), decl.bindingSpecifier.tokenKind == .keyword(.var)
            else { continue }
            for binding in decl.bindings where binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name {
                let annotation = binding.typeAnnotation?.type.trimmedDescription
                guard let value = binding.initializer?.value else { return false }
                if value.is(StringLiteralExprSyntax.self) { return annotation == nil || annotation == "String" }
                // Amendment A (§10): an array literal of any elements; the initial lines are frame, and no
                // obligation reads them.
                if let array = value.as(ArrayExprSyntax.self) {
                    if array.elements.isEmpty { return annotation.map(arrayReturns.contains) ?? false }
                    let literals = array.elements.allSatisfy { $0.expression.is(StringLiteralExprSyntax.self) }
                    return annotation.map(arrayReturns.contains) ?? literals
                }
                if let call = value.as(FunctionCallExprSyntax.self), call.arguments.isEmpty {
                    let callee = call.calledExpression.trimmedDescription
                    return callee == "String" || arrayReturns.contains(callee)
                }
                return false
            }
        }
        return false
    }
}

/// Every `return` in a body, outside nested closures and functions.
final class ReturnCollector: SyntaxVisitor {
    var returns: [ReturnStmtSyntax] = []
    static func collect(_ body: CodeBlockSyntax) -> [ReturnStmtSyntax] {
        let collector = ReturnCollector(viewMode: .sourceAccurate)
        collector.walk(body)
        return collector.returns
    }
    override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind { returns.append(node); return .skipChildren }
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
}

/// The loop-level context (§2.3–§2.5).
struct LoopContext {
    var elementText: Set<String> = []
    var opaque: Set<String> = []
    var opaqueCalls: [String: FunctionCallExprSyntax] = [:]
    var guards: [String] = []
    var callGuarded = false
    var depth = 0
    var sources: [String] = []
    var widened = false

    var tracked: Set<String> { elementText.union(opaque) }
}

struct BodyWalker {
    let accumulator: String
    let parameters: Set<String>
    let parameterTypes: [String: String]
    let isInstance: Bool
    let topLocals: Set<String>
    let index: FunctionIndex
    let converter: SourceLocationConverter

    var obligations: [Obligation] = []
    var loops: [String] = []
    var rowRefusal: String?
    var postLoopRefusal: String?
    var sawW1 = false
    var topLevelGuards: [String] = []

    // MARK: Top level

    mutating func walkTop(_ items: CodeBlockItemListSyntax, guards: [String] = []) {
        var sawQualifying = false
        for item in items {
            if let forStmt = item.item.as(ForStmtSyntax.self) {
                if walkLoop(forStmt, outer: LoopContext(guards: guards)) {
                    sawQualifying = true
                    postLoopRefusal = nil
                }
                continue
            }
            if let ifExpr = ifExpr(of: item) {
                let before = obligations.count
                walkTopIf(ifExpr, guards: guards)
                if obligations.count > before { sawQualifying = true; postLoopRefusal = nil }
                continue
            }
            if sawQualifying, let refusal = tailMutation(item) { postLoopRefusal = refusal }
        }
    }

    mutating func walkTopIf(_ ifExpr: IfExprSyntax, guards: [String]) {
        let (condition, restatable) = conditionText(ifExpr.conditions, tracked: [])
        let thenGuards = guards + [restatable ? condition : "⟨unrestatable: \(condition)⟩"]
        walkTop(ifExpr.body.statements, guards: thenGuards)
        switch ifExpr.elseBody {
        case .ifExpr(let next)?: walkTopIf(next, guards: guards + ["!(\(condition))"])
        case .codeBlock(let block)?: walkTop(block.statements, guards: guards + ["!(\(condition))"])
        case nil: break
        }
    }

    func ifExpr(of item: CodeBlockItemSyntax) -> IfExprSyntax? {
        if let expr = item.item.as(ExprSyntax.self) { return expr.as(IfExprSyntax.self) }
        if let stmt = item.item.as(ExpressionStmtSyntax.self) { return stmt.expression.as(IfExprSyntax.self) }
        return nil
    }

    /// §2.5: after the last qualifying loop, an accumulator statement other than an append of a literal.
    func tailMutation(_ item: CodeBlockItemSyntax) -> String? {
        let text = item.item.trimmedDescription
        guard text.contains(accumulator) else { return nil }
        if let (verb, argument) = accumulation(item.item) {
            if verb == "append" || verb == "+=" || verb == "append(contentsOf:)" {
                return isLiteral(argument) ? nil : "tail: \(text.prefix(60))"
            }
            return "tail: \(text.prefix(60))"
        }
        if item.item.is(ReturnStmtSyntax.self) { return nil }
        if text.hasPrefix("return") { return nil }
        // Mentions of the accumulator that do not mutate it (e.g. `if lines.isEmpty`) are tolerated only when they
        // are not assignments or mutating calls.
        if let infix = exprOf(item.item)?.as(InfixOperatorExprSyntax.self),
           infix.leftOperand.trimmedDescription == accumulator { return "tail: \(text.prefix(60))" }
        if let call = exprOf(item.item)?.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           member.base?.trimmedDescription == accumulator { return "tail: \(text.prefix(60))" }
        return nil
    }

    func isLiteral(_ expr: ExprSyntax) -> Bool {
        if let literal = expr.as(StringLiteralExprSyntax.self) {
            return literal.segments.allSatisfy { $0.is(StringSegmentSyntax.self) }
        }
        if let array = expr.as(ArrayExprSyntax.self) { return array.elements.allSatisfy { isLiteral($0.expression) } }
        return false
    }

    func exprOf(_ item: CodeBlockItemSyntax.Item) -> ExprSyntax? {
        if let expr = item.as(ExprSyntax.self) { return expr }
        if let stmt = item.as(ExpressionStmtSyntax.self) { return stmt.expression }
        return nil
    }

    /// `acc.append(X)`, `acc.append(contentsOf: X)`, `acc += X`, or `acc.<verb>(X)` (verb returned as is).
    func accumulation(_ item: CodeBlockItemSyntax.Item) -> (String, ExprSyntax)? {
        guard let expr = exprOf(item) else { return nil }
        if let infix = expr.as(InfixOperatorExprSyntax.self),
           infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "+=",
           infix.leftOperand.trimmedDescription == accumulator {
            return ("+=", infix.rightOperand)
        }
        if let call = expr.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           member.base?.trimmedDescription == accumulator,
           let first = call.arguments.first {
            let verb = member.declName.baseName.text
            if verb == "append" {
                return (first.label?.text == "contentsOf" ? "append(contentsOf:)" : "append", first.expression)
            }
            return (verb, first.expression)
        }
        return nil
    }

    // MARK: Loops

    enum SourceKind { case qualifying, widened, refusedString, refusedCharacter, other }

    /// A parameter path: a parameter (or `self`, or in an instance method an implicit member) followed by member
    /// accesses and no calls. `extraRoots` are names a nested loop may root at.
    func isParameterPath(_ expr: ExprSyntax, extraRoots: Set<String>, locals: Set<String>) -> Bool {
        var current = expr
        while let member = current.as(MemberAccessExprSyntax.self) {
            guard let base = member.base else { return false }
            current = base
        }
        if let ref = current.as(DeclReferenceExprSyntax.self) {
            let name = ref.baseName.text
            if extraRoots.contains(name) || parameters.contains(name) || name == "self" { return true }
            if isInstance, !locals.contains(name), !topLocals.contains(name) { return true }
        }
        return false
    }

    func classifySource(_ sequence: ExprSyntax, pattern: [String], context: LoopContext) -> SourceKind {
        if pattern.contains(where: Reader.characterNames.contains) { return .refusedCharacter }
        if let member = sequence.as(MemberAccessExprSyntax.self), Reader.stringViews.contains(member.declName.baseName.text) {
            return .refusedString
        }
        if let ref = sequence.as(DeclReferenceExprSyntax.self), parameterTypes[ref.baseName.text] == "String" {
            return .refusedString
        }
        if isParameterPath(sequence, extraRoots: context.tracked, locals: context.tracked) { return .qualifying }
        // W1: inline `P.sorted(…)` / `.enumerated()` / `.filter { … }`.
        if let call = sequence.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           Reader.widenOps.contains(member.declName.baseName.text),
           let base = member.base, isParameterPath(base, extraRoots: context.tracked, locals: context.tracked) {
            return .widened
        }
        if let call = sequence.as(FunctionCallExprSyntax.self), call.trailingClosure != nil,
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "filter",
           let base = member.base, isParameterPath(base, extraRoots: context.tracked, locals: context.tracked) {
            return .widened
        }
        return .other
    }

    func patternNames(_ pattern: PatternSyntax) -> [String]? {
        if let ident = pattern.as(IdentifierPatternSyntax.self) { return [ident.identifier.text] }
        if let tuple = pattern.as(TuplePatternSyntax.self) {
            var names: [String] = []
            for element in tuple.elements {
                if let inner = patternNames(element.pattern) { names += inner } else if element.pattern.is(WildcardPatternSyntax.self) {
                    continue
                } else { return nil }
            }
            return names
        }
        if let binding = pattern.as(ValueBindingPatternSyntax.self) { return patternNames(binding.pattern) }
        return nil
    }

    /// Reads one loop. Returns whether it was qualifying (or widened) and so may carry obligations.
    @discardableResult
    mutating func walkLoop(_ forStmt: ForStmtSyntax, outer: LoopContext) -> Bool {
        guard let names = patternNames(forStmt.pattern) else {
            loops.append("refused: pattern \(forStmt.pattern.trimmedDescription)")
            return false
        }
        let source = forStmt.sequence
        let kind = classifySource(source, pattern: names, context: outer)
        let label = "\(forStmt.pattern.trimmedDescription) in \(source.trimmedDescription.prefix(80))"
        switch kind {
        case .refusedString: loops.append("refused: string view: \(label)"); return false
        case .refusedCharacter: loops.append("refused: character loop: \(label)"); return false
        case .other:
            loops.append("refused: source other: \(label)")
            // Appends under an unread loop that reach tracked names are recorded, never statable.
            if !outer.tracked.isEmpty { recordUnread(forStmt.body, context: outer, reason: "nested: source other") }
            return false
        case .widened:
            sawW1 = true
            loops.append("W1: \(label)")
        case .qualifying:
            loops.append("qualifying: \(label)")
        }
        if containsExit(forStmt.body) { rowRefusal = rowRefusal ?? "exit in loop" }
        var context = outer
        context.elementText.formUnion(names)
        context.depth += 1
        context.sources.append(source.trimmedDescription)
        context.widened = outer.widened || kind == .widened
        if let condition = forStmt.whereClause?.condition {
            let (text, ok) = expressionGuard(condition, tracked: context.tracked)
            if ok { context.guards.append(text) } else { context.callGuarded = true; context.guards.append("⟨\(text)⟩") }
        }
        walkBlock(forStmt.body.statements, context: context)
        return true
    }

    /// `break` (not a switch's), `return` or `throw` inside a loop, outside nested closures and functions.
    func containsExit(_ body: CodeBlockSyntax) -> Bool {
        final class ExitFinder: SyntaxVisitor {
            var found = false
            override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind { found = true; return .skipChildren }
            override func visit(_ node: ThrowStmtSyntax) -> SyntaxVisitorContinueKind { found = true; return .skipChildren }
            override func visit(_ node: BreakStmtSyntax) -> SyntaxVisitorContinueKind {
                if node.label != nil { found = true; return .skipChildren }
                var parent = node.parent
                while let current = parent {
                    if current.is(SwitchExprSyntax.self) { return .skipChildren }
                    if current.is(ForStmtSyntax.self) || current.is(WhileStmtSyntax.self) || current.is(RepeatStmtSyntax.self) {
                        found = true; return .skipChildren
                    }
                    parent = current.parent
                }
                return .skipChildren
            }
            override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
            override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
        }
        let finder = ExitFinder(viewMode: .sourceAccurate)
        finder.walk(body)
        return finder.found
    }

    mutating func walkBlock(_ items: CodeBlockItemListSyntax, context start: LoopContext) {
        var context = start
        for item in items {
            if let decl = item.item.as(VariableDeclSyntax.self) {
                for binding in decl.bindings {
                    guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
                    let isVar = decl.bindingSpecifier.tokenKind == .keyword(.var)
                    if let value = binding.initializer?.value, reads(value, context.tracked) {
                        if !isVar, isElementTextForm(value, context) {
                            context.elementText.insert(name)
                        } else {
                            context.opaque.insert(name)
                            if let call = value.as(FunctionCallExprSyntax.self) { context.opaqueCalls[name] = call }
                        }
                    } else if isVar {
                        context.opaque.insert(name)
                    }
                }
                continue
            }
            if let forStmt = item.item.as(ForStmtSyntax.self) {
                walkLoop(forStmt, outer: context)
                continue
            }
            if let guardStmt = item.item.as(GuardStmtSyntax.self) {
                let continues = guardStmt.body.statements.contains { $0.item.is(ContinueStmtSyntax.self) }
                let (text, ok) = conditionText(guardStmt.conditions, tracked: context.tracked)
                if continues, ok { context.guards.append(text) } else {
                    context.callGuarded = true
                    context.guards.append("⟨guard \(text)⟩")
                    // Names bound by `guard let` are opaque.
                    for condition in guardStmt.conditions {
                        if let binding = condition.condition.as(OptionalBindingConditionSyntax.self),
                           let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                            context.opaque.insert(name)
                        }
                    }
                }
                continue
            }
            if let ifExpr = ifExpr(of: item) {
                walkIf(ifExpr, context: context)
                continue
            }
            if let switchExpr = exprOf(item.item)?.as(SwitchExprSyntax.self) {
                var inner = context
                inner.callGuarded = true
                inner.guards.append("⟨switch \(switchExpr.subject.trimmedDescription)⟩")
                for case let .switchCase(switchCase) in switchExpr.cases {
                    walkBlock(switchCase.statements, context: inner)
                }
                continue
            }
            if let whileStmt = item.item.as(WhileStmtSyntax.self) {
                var inner = context
                inner.callGuarded = true
                inner.guards.append("⟨while⟩")
                walkBlock(whileStmt.body.statements, context: inner)
                continue
            }
            if let doStmt = item.item.as(DoStmtSyntax.self) {
                walkBlock(doStmt.body.statements, context: context)
                continue
            }
            if let (verb, argument) = accumulation(item.item) {
                guard reads(argument, context.tracked) else { continue }
                record(verb: verb, argument: argument, item: item, context: context)
            }
        }
    }

    mutating func walkIf(_ ifExpr: IfExprSyntax, context: LoopContext) {
        let (condition, ok) = conditionText(ifExpr.conditions, tracked: context.tracked)
        var thenContext = context
        if ok { thenContext.guards.append(condition) } else {
            thenContext.callGuarded = true
            thenContext.guards.append("⟨\(condition)⟩")
            for element in ifExpr.conditions {
                if let binding = element.condition.as(OptionalBindingConditionSyntax.self),
                   let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                    thenContext.opaque.insert(name)
                }
            }
        }
        walkBlock(ifExpr.body.statements, context: thenContext)
        var elseContext = context
        if ok { elseContext.guards.append("!(\(condition))") } else {
            elseContext.callGuarded = true
            elseContext.guards.append("⟨!(\(condition))⟩")
        }
        switch ifExpr.elseBody {
        case .ifExpr(let next)?: walkIf(next, context: elseContext)
        case .codeBlock(let block)?: walkBlock(block.statements, context: elseContext)
        case nil: break
        }
    }

    mutating func recordUnread(_ body: CodeBlockSyntax, context: LoopContext, reason: String) {
        final class AppendFinder: SyntaxVisitor {
            var items: [CodeBlockItemSyntax] = []
            override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind { items.append(node); return .visitChildren }
        }
        let finder = AppendFinder(viewMode: .sourceAccurate)
        finder.walk(body)
        for item in finder.items {
            guard let (_, argument) = accumulation(item.item), reads(argument, context.tracked) else { continue }
            obligations.append(Obligation(
                line: line(of: item), kind: reason, statement: item.trimmedDescription, template: nil,
                guards: context.guards, depth: context.depth + 1, sources: context.sources, encoders: [],
                helper: nil, widened: context.widened
            ))
        }
    }

    func line(of node: some SyntaxProtocol) -> Int {
        converter.location(for: node.positionAfterSkippingLeadingTrivia).line
    }

    // MARK: Guards (§2.5)

    func conditionText(_ conditions: ConditionElementListSyntax, tracked: Set<String>) -> (String, Bool) {
        var parts: [String] = []
        var ok = true
        for element in conditions {
            if let expr = element.condition.as(ExprSyntax.self) {
                let (text, good) = expressionGuard(expr, tracked: tracked)
                parts.append(text)
                ok = ok && good
            } else {
                parts.append(element.condition.trimmedDescription)
                ok = false
            }
        }
        return (parts.joined(separator: " && "), ok)
    }

    /// Restatable when built only from tracked or parameter paths, literals, comparisons, `!`, `&&`, `||`,
    /// parentheses and `.isEmpty`.
    func expressionGuard(_ expr: ExprSyntax, tracked: Set<String>) -> (String, Bool) {
        (expr.trimmedDescription, restatable(expr, tracked: tracked))
    }

    func restatable(_ expr: ExprSyntax, tracked: Set<String>) -> Bool {
        if expr.is(StringLiteralExprSyntax.self) || expr.is(IntegerLiteralExprSyntax.self)
            || expr.is(BooleanLiteralExprSyntax.self) || expr.is(NilLiteralExprSyntax.self)
            || expr.is(FloatLiteralExprSyntax.self) { return true }
        if let tuple = expr.as(TupleExprSyntax.self), tuple.elements.count == 1 {
            return restatable(tuple.elements.first!.expression, tracked: tracked)
        }
        if let prefix = expr.as(PrefixOperatorExprSyntax.self), prefix.operator.text == "!" {
            return restatable(prefix.expression, tracked: tracked)
        }
        if let infix = expr.as(InfixOperatorExprSyntax.self),
           let op = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text,
           ["==", "!=", "<", "<=", ">", ">=", "&&", "||"].contains(op) {
            return restatable(infix.leftOperand, tracked: tracked) && restatable(infix.rightOperand, tracked: tracked)
        }
        if let member = expr.as(MemberAccessExprSyntax.self), member.base == nil { return true } // `.someCase`
        if isParameterPath(expr, extraRoots: tracked, locals: tracked) { return true }
        return false
    }

    // MARK: Obligations (§2.4)

    func reads(_ expr: some SyntaxProtocol, _ names: Set<String>) -> Bool {
        guard !names.isEmpty else { return false }
        return NameReadFinder.reads(Syntax(expr), names)
    }

    /// A path rooted at an element-text name: `e`, `e.a.b` (no calls).
    func elementPath(_ expr: ExprSyntax, _ context: LoopContext) -> Bool {
        var current = expr
        while let member = current.as(MemberAccessExprSyntax.self) {
            guard let base = member.base else { return false }
            current = base
        }
        if let ref = current.as(DeclReferenceExprSyntax.self) { return context.elementText.contains(ref.baseName.text) }
        return false
    }

    /// Element text: a path of an element-text name, a one-argument encoder call on element text, or a string
    /// literal built only from element text and literal text.
    func isElementTextForm(_ expr: ExprSyntax, _ context: LoopContext) -> Bool {
        if elementPath(expr, context) { return true }
        if let call = expr.as(FunctionCallExprSyntax.self), call.arguments.count == 1, call.trailingClosure == nil,
           Reader.calleeName(call) != nil, let argument = call.arguments.first?.expression {
            return isElementTextForm(argument, context)
        }
        if let literal = expr.as(StringLiteralExprSyntax.self) {
            var any = false
            for segment in literal.segments {
                if let interp = segment.as(ExpressionSegmentSyntax.self) {
                    guard interp.expressions.count == 1, let inner = interp.expressions.first?.expression,
                          isElementTextForm(inner, context) else { return false }
                    any = true
                }
            }
            return any
        }
        return false
    }

    func encoderNames(_ expr: ExprSyntax) -> [String] {
        if let call = expr.as(FunctionCallExprSyntax.self), let name = Reader.calleeName(call),
           let argument = call.arguments.first?.expression {
            return [name] + encoderNames(argument)
        }
        return []
    }

    /// The pieces of an accumulated value.
    func pieces(_ expr: ExprSyntax, _ context: LoopContext) -> [Piece] {
        if let literal = expr.as(StringLiteralExprSyntax.self) {
            var result: [Piece] = []
            for segment in literal.segments {
                if let text = segment.as(StringSegmentSyntax.self) {
                    result.append(.literal(text.content.text))
                } else if let interp = segment.as(ExpressionSegmentSyntax.self), let inner = interp.expressions.first?.expression {
                    result += [piece(inner, context, inInterpolation: true)]
                }
            }
            return result
        }
        if let infix = expr.as(InfixOperatorExprSyntax.self),
           infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "+" {
            return pieces(infix.leftOperand, context) + pieces(infix.rightOperand, context)
        }
        if let tuple = expr.as(TupleExprSyntax.self), tuple.elements.count == 1 {
            return pieces(tuple.elements.first!.expression, context)
        }
        return [piece(expr, context, inInterpolation: false)]
    }

    func piece(_ expr: ExprSyntax, _ context: LoopContext, inInterpolation: Bool) -> Piece {
        if isElementTextForm(expr, context) {
            // A whole accumulated value that is a one-argument call on the element itself is a helper (§2.4).
            if !inInterpolation, let call = expr.as(FunctionCallExprSyntax.self) { return .helper(call) }
            return .element(expr.trimmedDescription)
        }
        if let call = expr.as(FunctionCallExprSyntax.self), reads(call, context.tracked) { return .helper(call) }
        if let ref = expr.as(DeclReferenceExprSyntax.self), let call = context.opaqueCalls[ref.baseName.text],
           reads(call, context.tracked) {
            return .helper(call)
        }
        return .cut(expr.trimmedDescription)
    }

    mutating func record(verb: String, argument: ExprSyntax, item: CodeBlockItemSyntax, context: LoopContext) {
        var values: [ExprSyntax] = [argument]
        if verb == "append(contentsOf:)", let array = argument.as(ArrayExprSyntax.self) {
            values = array.elements.map(\.expression).filter { reads($0, context.tracked) }
        }
        for value in values {
            var obligation = Obligation(
                line: line(of: item), kind: "", statement: item.trimmedDescription, template: nil,
                guards: context.guards, depth: context.depth, sources: context.sources,
                encoders: encoderNames(value), helper: nil, widened: context.widened
            )
            if !["append", "append(contentsOf:)", "+="].contains(verb) {
                obligation.kind = "W3"
            } else if context.callGuarded {
                obligation.kind = "call-guarded"
            } else {
                classify(&obligation, pieces(value, context), tracked: context.tracked)
            }
            obligations.append(obligation)
        }
    }

    func classify(_ obligation: inout Obligation, _ pieces: [Piece], tracked: Set<String>) {
        if let helperCall = pieces.compactMap({ if case let .helper(call) = $0 { return call } else { return nil } }).first {
            obligation.kind = "helper"
            obligation.helper = HelperHop.resolve(helperCall, tracked: tracked, index: index, depth: 1)
            return
        }
        let (template, hasElement, hasCut, distinctive) = Self.run(pieces)
        if !hasElement { obligation.kind = "opaque"; return }
        obligation.template = template
        if distinctive { obligation.kind = hasCut ? "segment" : "primary" } else {
            obligation.kind = hasCut ? "segment: nothing distinctive" : "bare"
        }
    }

    /// The best run of pieces around element text, split at cuts: (template, any element, any cut, distinctive).
    static func run(_ pieces: [Piece]) -> (String?, Bool, Bool, Bool) {
        var runs: [[Piece]] = [[]]
        var hasCut = false
        for piece in pieces {
            if case .cut = piece { hasCut = true; runs.append([]) } else { runs[runs.count - 1].append(piece) }
        }
        var best: (String, Int)?
        var hasElement = false
        for run in runs {
            let element = run.contains { if case .element = $0 { return true } else { return false } }
            guard element else { continue }
            hasElement = true
            let literal = run.compactMap { if case let .literal(text) = $0 { return text } else { return nil } }.joined()
            let weight = literal.filter { !$0.isWhitespace }.count
            let template = run.map { piece -> String in
                switch piece {
                case let .literal(text): return text
                case let .element(text): return "⟨\(text)⟩"
                default: return ""
                }
            }.joined()
            if best == nil || weight > best!.1 { best = (template, weight) }
        }
        guard let chosen = best else { return (nil, hasElement, hasCut, false) }
        return (chosen.0, hasElement, hasCut, chosen.1 > 0)
    }
}
