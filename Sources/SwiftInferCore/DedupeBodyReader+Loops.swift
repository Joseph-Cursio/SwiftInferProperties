import SwiftSyntax

/// Every `return` in a body, outside the closures and nested functions it declares.
final class DedupeReturnCollector: SyntaxVisitor {
    var found: [ReturnStmtSyntax] = []

    override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind {
        found.append(node)
        return .visitChildren
    }

    override func visit(_: ClosureExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

    override func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
}

extension DedupeBodyReader {

    /// The `var` locals a dedupe body declares before its loop, by kind.
    /// The kind of empty collection a dedupe body's `var` local starts as.
    enum LocalKind { case set, dictionary, array }

    /// What a Set-route loop owes, and what it has shown so far.
    struct SetLoopProgress {
        /// An insert's success guards every later statement: a `where` clause or a `guard`.
        var guarded = false
        /// A `where !s.contains(k)` clause, whose body must insert `k`.
        var pendingKey: String?
        var inserted = false
        var appended = false
    }

    struct Locals {
        var sets: [String] = []
        var dictionaries: [String] = []
        var arrays: [String] = []

        init(_ items: ArraySlice<CodeBlockItemSyntax.Item>) {
            for item in items {
                guard let (name, kind) = Self.local(item) else { continue }
                switch kind {
                case .set: sets.append(name)
                case .dictionary: dictionaries.append(name)
                case .array: arrays.append(name)
                }
            }
        }

        /// An empty `Set`, dictionary or array `var`, as `Set<K>()`, `: Set<K> = []`, `[K: V]()`,
        /// `: [K: V] = [:]`, `[T]()` or `: [T] = []`; `nil` for anything else.
        static func local(_ item: CodeBlockItemSyntax.Item) -> (String, LocalKind)? {
            guard let decl = item.as(VariableDeclSyntax.self), decl.bindingSpecifier.tokenKind == .keyword(.var),
                  decl.bindings.count == 1, let binding = decl.bindings.first,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let initial = binding.initializer?.value else {
                return nil
            }
            if let annotation = binding.typeAnnotation?.type {
                return annotated(annotation, initial: initial).map { (name, $0) }
            }
            guard let call = initial.as(FunctionCallExprSyntax.self), call.arguments.isEmpty,
                  call.trailingClosure == nil else {
                return nil
            }
            let callee = call.calledExpression
            if callee.as(GenericSpecializationExprSyntax.self)?.expression.trimmedDescription == "Set" {
                return (name, .set)
            }
            if callee.is(DictionaryExprSyntax.self) { return (name, .dictionary) }
            if callee.is(ArrayExprSyntax.self) { return (name, .array) }
            return nil
        }

        private static func annotated(_ annotation: TypeSyntax, initial: ExprSyntax) -> LocalKind? {
            let text = initial.trimmedDescription
            if annotation.as(IdentifierTypeSyntax.self)?.name.text == "Set" {
                let emptyCall = text == "Set()" || (text.hasPrefix("Set<") && text.hasSuffix(">()"))
                return text == "[]" || emptyCall ? .set : nil
            }
            if annotation.is(DictionaryTypeSyntax.self) { return text == "[:]" ? .dictionary : nil }
            if DedupeBodyReader.element(of: annotation) != nil { return text == "[]" ? .array : nil }
            return nil
        }
    }

    /// The Set route's loop: every `r.append(x)` reached only through a successful insert.
    struct SetLoop {
        let set: String
        let array: String
        let element: String

        func read(_ loop: ForStmtSyntax) -> Reading {
            var progress = SetLoopProgress()
            if let clause = loop.whereClause?.condition {
                if DedupeBodyReader.insertedKey(clause, set: set) != nil {
                    progress.guarded = true
                } else if let key = DedupeBodyReader.absentKey(clause, set: set) {
                    progress.pendingKey = key
                } else {
                    return .refused(Refusal.otherSkip)
                }
                guard isClean(clause) else { return .refused(Refusal.unread) }
            }
            for item in loop.body.statements.map(\.item) {
                if let refusal = step(item, &progress) { return .refused(refusal) }
            }
            guard progress.appended, progress.pendingKey == nil || progress.inserted else {
                return .refused(Refusal.unread)
            }
            return .admitted(DedupeBody(route: .set))
        }

        /// One loop statement; the refusal, or `nil` when it is allowed.
        private func step(_ item: CodeBlockItemSyntax.Item, _ progress: inout SetLoopProgress) -> String? {
            if let refusal = letRefusal(item) { return refusal.isEmpty ? nil : refusal }
            if isAppend(item) {
                guard progress.guarded || progress.pendingKey != nil else { return Refusal.appendNotBehindInsert }
                // One append per element: a second would make `f([x]).count == 2`, and C1 false.
                guard !progress.appended else { return Refusal.unread }
                progress.appended = true
                return nil
            }
            if let key = progress.pendingKey, insertKey(item) == key, isClean(item) {
                progress.inserted = true
                return nil
            }
            if let guardStatement = item.as(GuardStmtSyntax.self) {
                return readGuard(guardStatement, &progress)
            }
            if let branch = DedupeBodyReader.ifExpression(item), let verdict = readBranch(branch) {
                guard verdict == nil else { return verdict }
                guard !progress.appended else { return Refusal.unread }
                progress.appended = true
                return nil
            }
            if DedupeBodyReader.appends(to: array, in: item) { return Refusal.appendNotBehindInsert }
            return DedupeBodyReader.skips(item) ? Refusal.otherSkip : Refusal.unread
        }

        /// `guard s.insert(k).inserted else { continue }`, which guards every later statement.
        private func readGuard(_ statement: GuardStmtSyntax, _ progress: inout SetLoopProgress) -> String? {
            if let condition = DedupeBodyReader.singleCondition(statement.conditions),
               isClean(condition), DedupeBodyReader.insertedKey(condition, set: set) != nil,
               DedupeBodyReader.isContinueOnly(statement.body) {
                progress.guarded = true
                return nil
            }
            let appended = DedupeBodyReader.appends(to: array, in: statement)
            return appended ? Refusal.appendNotBehindInsert : Refusal.otherSkip
        }

        /// `if s.insert(k).inserted { … }` or `if !s.contains(k) { s.insert(k); … }`, with no
        /// `else`. `.some(nil)` admits the branch, `.some(reason)` refuses it, and `nil` says the
        /// `if` is not an insert branch at all.
        private func readBranch(_ branch: IfExprSyntax) -> String?? {
            guard branch.elseBody == nil,
                  let condition = DedupeBodyReader.singleCondition(branch.conditions) else { return nil }
            guard isClean(condition) else { return .some(Refusal.unread) }
            var pendingKey: String?
            if DedupeBodyReader.insertedKey(condition, set: set) == nil {
                guard let key = DedupeBodyReader.absentKey(condition, set: set) else { return nil }
                pendingKey = key
            }
            var inserted = pendingKey == nil
            var appended = false
            for item in branch.body.statements.map(\.item) {
                if let refusal = letRefusal(item) {
                    if refusal.isEmpty { continue }
                    return .some(refusal)
                }
                if let key = pendingKey, insertKey(item) == key, isClean(item) {
                    inserted = true
                } else if isAppend(item), !appended {
                    appended = true
                } else {
                    return .some(Refusal.unread)
                }
            }
            return appended && inserted ? .some(nil) : .some(Refusal.unread)
        }

        /// For a `let`: `""` when it is inert (a key's computation), a refusal when it touches the set
        /// or the result. `nil` when the item is not a `let`.
        ///
        /// A `let` is read, not waved through: `let _ = seen.insert(x)` pre-inserts a key and
        /// `let _ = result.append(x)` appends outside any insert. Either makes C1 or C2 false of the
        /// function as written.
        private func letRefusal(_ item: CodeBlockItemSyntax.Item) -> String? {
            guard let decl = item.as(VariableDeclSyntax.self), decl.bindingSpecifier.tokenKind == .keyword(.let) else {
                return nil
            }
            if DedupeBodyReader.appends(to: array, in: decl) { return Refusal.appendNotBehindInsert }
            return DedupeBodyReader.mentions([set, array], in: decl) ? Refusal.unread : ""
        }

        /// An insert or `contains` that names the set once, as its receiver, and never the result: a
        /// key computed from `seen` or from `result` is not a key of the element.
        private func isClean(_ node: some SyntaxProtocol) -> Bool {
            DedupeBodyReader.occurrences(of: set, in: node) == 1 && !DedupeBodyReader.mentions([array], in: node)
        }

        /// `r.append(x)`, with `x` the loop variable.
        private func isAppend(_ item: CodeBlockItemSyntax.Item) -> Bool {
            guard let call = item.as(FunctionCallExprSyntax.self) else { return false }
            return DedupeBodyReader.argument(of: call, on: array, named: "append") == element
        }

        /// The key of a bare `s.insert(k)` statement.
        private func insertKey(_ item: CodeBlockItemSyntax.Item) -> String? {
            item.as(FunctionCallExprSyntax.self).flatMap { DedupeBodyReader.argument(of: $0, on: set, named: "insert") }
        }
    }

    /// The dictionary route's loop: writes `d[k] = x`, and skips only where `d[k]` is read.
    struct DictionaryLoop {
        let dictionary: String
        let element: String

        func read(_ loop: ForStmtSyntax) -> Reading {
            guard loop.whereClause == nil else { return .refused(Refusal.otherSkip) }
            var writtenKeys: Set<String> = []
            var readKeys: Set<String> = []
            for item in loop.body.statements.map(\.item) {
                if let decl = item.as(VariableDeclSyntax.self), decl.bindingSpecifier.tokenKind == .keyword(.let) {
                    guard !DedupeBodyReader.mentions([dictionary], in: decl) else { return .refused(Refusal.unread) }
                    continue
                }
                if let key = writeKey(item), DedupeBodyReader.occurrences(of: dictionary, in: item) == 1 {
                    writtenKeys.insert(key)
                } else if let key = presenceSkipKey(item) {
                    readKeys.insert(key)
                } else {
                    return .refused(DedupeBodyReader.skips(item) ? Refusal.otherSkip : Refusal.unread)
                }
            }
            // One key throughout: every element's key ends with an entry, and a skip only passes over
            // an element whose key already has one.
            guard writtenKeys.count == 1, readKeys.isSubset(of: writtenKeys) else { return .refused(Refusal.unread) }
            return .admitted(DedupeBody(route: .dictionary))
        }

        /// The key of `d[k] = x`, with `x` the loop variable, at the loop's top level.
        private func writeKey(_ item: CodeBlockItemSyntax.Item) -> String? {
            guard let expression = item.as(ExprSyntax.self),
                  let parts = DedupeBodyReader.binaryParts(expression), parts.count == 3,
                  parts[1].is(AssignmentExprSyntax.self),
                  parts[2].trimmedDescription == element else { return nil }
            return subscriptKey(parts[0])
        }

        /// The key of `if <d[k] is present>, … { continue }`, or `nil` for any other statement.
        ///
        /// The first condition must be a presence test on one key, `let v = d[k]` or `d[k] != nil`,
        /// and the others may only narrow it: they are conjuncts, and none may name `d`. So the skip
        /// fires only where the key already has an entry. Merely *mentioning* `d[k]` is not enough:
        /// `d[k] != nil || x < 0` and `x < 0, d[k] == nil` also filter, and C1 is false of a filter.
        private func presenceSkipKey(_ item: CodeBlockItemSyntax.Item) -> String? {
            guard let branch = DedupeBodyReader.ifExpression(item), branch.elseBody == nil,
                  DedupeBodyReader.isContinueOnly(branch.body),
                  let first = branch.conditions.first, let key = presenceKey(first.condition),
                  DedupeBodyReader.occurrences(of: dictionary, in: first) == 1,
                  !narrowingNamesDictionary(branch.conditions) else {
                return nil
            }
            return key
        }

        /// Whether a condition after the first names `d`: a conjunct may narrow the skip, not consult `d`.
        private func narrowingNamesDictionary(_ conditions: ConditionElementListSyntax) -> Bool {
            conditions.dropFirst().contains { DedupeBodyReader.mentions([dictionary], in: $0) }
        }

        /// The key of `let v = d[k]` or `d[k] != nil`.
        private func presenceKey(_ condition: ConditionElementSyntax.Condition) -> String? {
            switch condition {
            case .optionalBinding(let binding):
                return binding.initializer.flatMap { subscriptKey($0.value) }

            case .expression(let expression):
                guard let parts = DedupeBodyReader.binaryParts(expression), parts.count == 3,
                      parts[1].as(BinaryOperatorExprSyntax.self)?.operator.text == "!=",
                      parts[2].is(NilLiteralExprSyntax.self) else {
                    return nil
                }
                return subscriptKey(parts[0])

            default:
                return nil
            }
        }

        /// The key text of `d[k]`, or `nil` when `expression` subscripts anything else.
        private func subscriptKey(_ expression: some ExprSyntaxProtocol) -> String? {
            guard let call = ExprSyntax(expression).as(SubscriptCallExprSyntax.self),
                  call.calledExpression.trimmedDescription == dictionary,
                  call.arguments.count == 1, let only = call.arguments.first, only.label == nil else {
                return nil
            }
            return only.expression.trimmedDescription
        }
    }

    /// An operator expression's operands and operators in source order, folded or not; `nil` for any
    /// other expression.
    static func binaryParts(_ expression: ExprSyntax) -> [ExprSyntax]? {
        if let infix = expression.as(InfixOperatorExprSyntax.self) {
            return [infix.leftOperand, infix.operator, infix.rightOperand]
        }
        return expression.as(SequenceExprSyntax.self).map { Array($0.elements) }
    }

    /// How many identifier tokens in `node` spell `name`.
    static func occurrences(of name: String, in node: some SyntaxProtocol) -> Int {
        node.tokens(viewMode: .sourceAccurate).filter { token in
            guard case .identifier(let text) = token.tokenKind else { return false }
            return text == name
        }.count
    }

    /// Whether any identifier token in `node` spells one of `names`.
    static func mentions(_ names: [String], in node: some SyntaxProtocol) -> Bool {
        names.contains { occurrences(of: $0, in: node) > 0 }
    }

    /// The sole expression condition of a `guard` or `if`.
    static func singleCondition(_ conditions: ConditionElementListSyntax) -> ExprSyntax? {
        guard conditions.count == 1, case .expression(let expression) = conditions.first?.condition else {
            return nil
        }
        return expression
    }

    static func isContinueOnly(_ block: CodeBlockSyntax) -> Bool {
        block.statements.count == 1 && block.statements.first?.item.is(ContinueStmtSyntax.self) == true
    }

    /// The `if` an item is, whether it parses as a statement or an expression.
    static func ifExpression(_ item: CodeBlockItemSyntax.Item) -> IfExprSyntax? {
        item.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self) ?? item.as(IfExprSyntax.self)
    }
}
