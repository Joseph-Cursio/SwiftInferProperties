import SwiftSyntax

/// §2.1: the name family, #671's grep done on the name token.
enum NameFamily {
    static let prefixes = ["dedup", "uniqu", "distinct", "removingduplicate", "removeduplicate"]

    static func contains(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return prefixes.contains { lowered.hasPrefix($0) }
    }
}

/// §2.2: the name gate.
enum NameGate {
    static let stems: [[String]] = [
        ["dedupe"], ["deduplicate"], ["deduplicated"], ["deduped"], ["uniqued"], ["uniquing"],
        ["removing", "Duplicates"],
    ]
    static let recognisedToday: Set<String> = ["dedupe", "deduplicate", "deduplicated"]

    /// Camel-case words: `dedupedByStateAndAction` → `deduped`, `By`, `State`, `And`, `Action`.
    static func words(_ name: String) -> [String] {
        var words: [String] = []
        var current = ""
        for character in name {
            if character.isUppercase, !current.isEmpty, current.last?.isUppercase == false {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// `nil` when the name passes, otherwise the refusal.
    static func refusal(_ name: String) -> String? {
        let parts = words(name)
        guard let stem = stems.first(where: { parts.starts(with: $0) }) else { return "name: not a stem" }
        let tail = Array(parts.dropFirst(stem.count))
        if tail.isEmpty { return nil }
        if tail.contains(where: { $0.hasPrefix("Adjacent") || $0.hasPrefix("Consecutive") }) {
            return "name: revoking tail"
        }
        return tail.first == "By" ? nil : "name: other tail"
    }
}

/// §2.3: the shape gate.
enum ShapeGate {
    enum Form: String, Codable { case parameter, receiver }

    static let keyClosureLabels: Set<String> = ["on", "by", "using", "keyPath"]
    static let receiverTypes: Set<String> = ["Array", "Sequence", "Collection"]

    struct Reading {
        let form: Form
        /// The parameter's name, or `self`.
        let input: String
        let element: String
    }

    /// `[T]` or `Array<T>` → `T`.
    static func element(of type: TypeSyntax) -> String? {
        if let array = type.as(ArrayTypeSyntax.self) { return array.element.trimmedDescription }
        if let identifier = type.as(IdentifierTypeSyntax.self), identifier.name.text == "Array",
           let arguments = identifier.genericArgumentClause?.arguments, arguments.count == 1 {
            return arguments.first?.argument.trimmedDescription
        }
        return nil
    }

    static func read(_ function: FunctionDeclSyntax, extendedType: String?) -> Result<Reading, Refusal> {
        let effects = function.signature.effectSpecifiers
        if effects?.asyncSpecifier != nil || effects?.throwsClause != nil {
            return .failure(Refusal("shape: effects"))
        }
        if function.modifiers.contains(where: { $0.name.tokenKind == .keyword(.mutating) }) {
            return .failure(Refusal("shape: mutating"))
        }
        guard let returned = function.signature.returnClause?.type, let returnElement = element(of: returned) else {
            return .failure(Refusal("shape: return"))
        }
        let parameters = Array(function.signature.parameterClause.parameters)
        switch parameters.count {
        case 1:
            let parameter = parameters[0]
            if let attributed = parameter.type.as(AttributedTypeSyntax.self), !attributed.specifiers.isEmpty {
                return .failure(Refusal("shape: inout or ownership"))
            }
            guard let parameterElement = element(of: parameter.type), parameterElement == returnElement else {
                return .failure(Refusal("shape: parameter"))
            }
            if keyClosureLabels.contains(parameter.firstName.text) {
                return .failure(Refusal("shape: key-closure label"))
            }
            let name = (parameter.secondName ?? parameter.firstName).text
            return .success(Reading(form: .parameter, input: name, element: parameterElement))

        case 0:
            guard let extendedType, receiverTypes.contains(extendedType), returnElement == "Element" else {
                return .failure(Refusal("shape: parameters"))
            }
            return .success(Reading(form: .receiver, input: "self", element: "Element"))

        default:
            return .failure(Refusal("shape: parameters"))
        }
    }
}

struct Refusal: Error, Equatable {
    let reason: String
    init(_ reason: String) { self.reason = reason }
}

/// §2.4: the body gate.
enum BodyGate {
    enum Route: String, Codable { case set, dictionary }

    struct Reading: Equatable {
        let route: Route
        let keepFirst: Bool
    }

    static let noLocal = "body: no set or dictionary local"
    static let appendNotBehindInsert = "body: append not behind an insert"
    static let earlyReturn = "body: early return"
    static let otherSkip = "body: other skip"
    static let unread = "body: unread form"

    enum LocalKind { case set, dictionary, array }

    /// `var name … = …` with one binding, classified by its annotation or initialiser.
    static func local(_ item: CodeBlockItemSyntax.Item) -> (name: String, kind: LocalKind)? {
        guard let decl = item.as(VariableDeclSyntax.self), decl.bindingSpecifier.tokenKind == .keyword(.var),
              decl.bindings.count == 1, let binding = decl.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return nil }
        let annotation = binding.typeAnnotation?.type
        let initial = binding.initializer?.value
        let initialText = initial?.trimmedDescription ?? ""
        if let annotation {
            if let identifier = annotation.as(IdentifierTypeSyntax.self), identifier.name.text == "Set",
               ["[]", "Set()"].contains(initialText) || initialText.hasPrefix("Set<") && initialText.hasSuffix(">()") {
                return (name, .set)
            }
            if annotation.is(DictionaryTypeSyntax.self), initialText == "[:]" { return (name, .dictionary) }
            if annotation.is(ArrayTypeSyntax.self), initialText == "[]" { return (name, .array) }
            return nil
        }
        guard let call = initial?.as(FunctionCallExprSyntax.self), call.arguments.isEmpty,
              call.trailingClosure == nil else { return nil }
        let callee = call.calledExpression
        if let generic = callee.as(GenericSpecializationExprSyntax.self),
           generic.expression.trimmedDescription == "Set" { return (name, .set) }
        if callee.is(DictionaryExprSyntax.self) { return (name, .dictionary) }
        if callee.is(ArrayExprSyntax.self) { return (name, .array) }
        return nil
    }

    /// Every `return` in the body outside closures and nested functions.
    final class ReturnCounter: SyntaxVisitor {
        var returns: [ReturnStmtSyntax] = []
        override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind {
            returns.append(node)
            return .visitChildren
        }
        override func visit(_: ClosureExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
        override func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    }

    /// Whether any `X.append(…)` call on `array` occurs under `node`.
    static func appends(to array: String, in node: some SyntaxProtocol) -> Bool {
        node.tokens(viewMode: .sourceAccurate).contains { token in
            guard token.text == "append", let member = token.parent?.parent?.as(MemberAccessExprSyntax.self) else {
                return false
            }
            return member.base?.trimmedDescription == array
        }
    }

    /// `s.insert(k).inserted`.
    static func isInsertedCheck(_ expression: ExprSyntax, set: String) -> Bool {
        guard let member = expression.as(MemberAccessExprSyntax.self), member.declName.baseName.text == "inserted",
              let call = member.base?.as(FunctionCallExprSyntax.self) else { return false }
        return isCall(call, on: set, named: "insert")
    }

    static func isCall(_ call: FunctionCallExprSyntax, on base: String, named name: String) -> Bool {
        guard let callee = call.calledExpression.as(MemberAccessExprSyntax.self) else { return false }
        return callee.base?.trimmedDescription == base && callee.declName.baseName.text == name
            && call.arguments.count == 1 && call.trailingClosure == nil
    }

    /// `r.append(x)` with `x` the loop variable.
    static func isAppend(_ item: CodeBlockItemSyntax.Item, array: String, element: String) -> Bool {
        guard let call = item.as(FunctionCallExprSyntax.self), isCall(call, on: array, named: "append") else {
            return false
        }
        return call.arguments.first?.label == nil && call.arguments.first?.expression.trimmedDescription == element
    }

    static func isLet(_ item: CodeBlockItemSyntax.Item) -> Bool {
        item.as(VariableDeclSyntax.self)?.bindingSpecifier.tokenKind == .keyword(.let)
    }

    static func singleCondition(_ conditions: ConditionElementListSyntax) -> ExprSyntax? {
        guard conditions.count == 1, case .expression(let expression) = conditions.first?.condition else { return nil }
        return expression
    }

    static func isContinueOnly(_ block: CodeBlockSyntax) -> Bool {
        block.statements.count == 1 && block.statements.first?.item.is(ContinueStmtSyntax.self) == true
    }

    /// What `item` returns, for the final statement: `return e` or a bare expression `e`.
    static func returned(_ item: CodeBlockItemSyntax.Item) -> ExprSyntax? {
        if let statement = item.as(ReturnStmtSyntax.self) { return statement.expression }
        return item.as(ExprSyntax.self)
    }

    static func read(_ body: CodeBlockSyntax, input: String) -> Result<Reading, Refusal> {
        let items = body.statements.map(\.item)
        guard let last = items.last else { return .failure(Refusal(noLocal)) }
        let counter = ReturnCounter(viewMode: .sourceAccurate)
        counter.walk(body)
        let finalReturn = last.as(ReturnStmtSyntax.self)
        if counter.returns.contains(where: { $0.id != finalReturn?.id }) { return .failure(Refusal(earlyReturn)) }

        var sets: [String] = []
        var dictionaries: [String] = []
        var arrays: [String] = []
        for item in items.dropLast() {
            if let found = local(item) {
                switch found.kind {
                case .set: sets.append(found.name)
                case .dictionary: dictionaries.append(found.name)
                case .array: arrays.append(found.name)
                }
            }
        }
        guard sets.count + dictionaries.count >= 1 else { return .failure(Refusal(noLocal)) }

        // The filter form: `var s = Set…; return in.filter { s.insert(k).inserted }`.
        if items.count == 2, sets.count == 1, let filtered = returned(last)?.as(FunctionCallExprSyntax.self),
           let callee = filtered.calledExpression.as(MemberAccessExprSyntax.self),
           callee.declName.baseName.text == "filter" {
            guard callee.base?.trimmedDescription == input, filtered.arguments.isEmpty,
                  let closure = filtered.trailingClosure, closure.statements.count == 1,
                  let only = closure.statements.first?.item.as(ExprSyntax.self),
                  isInsertedCheck(only, set: sets[0]) else { return .failure(Refusal(unread)) }
            return .success(Reading(route: .set, keepFirst: true))
        }

        // The loop forms: locals, one `for x in in`, and the final return.
        let loops = items.compactMap { $0.as(ForStmtSyntax.self) }
        guard loops.count == 1, let loop = loops.first,
              loop.sequence.trimmedDescription == input, loop.whereClause == nil, loop.tryKeyword == nil,
              loop.awaitKeyword == nil,
              let element = loop.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
            return .failure(Refusal(unread))
        }
        for item in items.dropLast() where !item.is(ForStmtSyntax.self) && local(item) == nil {
            let appended = arrays.contains { appends(to: $0, in: item) }
            return .failure(Refusal(appended ? appendNotBehindInsert : unread))
        }

        if sets.count == 1, arrays.count == 1, dictionaries.isEmpty,
           returned(last)?.trimmedDescription == arrays[0] {
            return readSetLoop(loop.body, set: sets[0], array: arrays[0], element: element)
        }
        if dictionaries.count == 1, sets.isEmpty, arrays.isEmpty,
           returned(last)?.trimmedDescription == "Array(\(dictionaries[0]).values)" {
            return readDictionaryLoop(loop.body, dictionary: dictionaries[0], element: element)
        }
        let appended = arrays.contains { appends(to: $0, in: last) }
        return .failure(Refusal(appended ? appendNotBehindInsert : unread))
    }

    static func readSetLoop(_ body: CodeBlockSyntax, set: String, array: String, element: String) -> Result<Reading, Refusal> {
        var behindGuard = false
        for item in body.statements.map(\.item) {
            if isLet(item) { continue }
            if isAppend(item, array: array, element: element) {
                if behindGuard { continue }
                return .failure(Refusal(appendNotBehindInsert))
            }
            if let guardStatement = item.as(GuardStmtSyntax.self) {
                if let condition = singleCondition(guardStatement.conditions), isInsertedCheck(condition, set: set),
                   isContinueOnly(guardStatement.body) {
                    behindGuard = true
                    continue
                }
                return .failure(Refusal(appends(to: array, in: guardStatement) ? appendNotBehindInsert : otherSkip))
            }
            if let ifExpression = item.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self)
                ?? item.as(IfExprSyntax.self) {
                if let verdict = readSetBranch(ifExpression, set: set, array: array, element: element) {
                    if case .failure = verdict { return verdict }
                    continue
                }
            }
            if appends(to: array, in: item) { return .failure(Refusal(appendNotBehindInsert)) }
            if item.tokens(viewMode: .sourceAccurate).contains(where: { $0.tokenKind == .keyword(.continue) }) {
                return .failure(Refusal(otherSkip))
            }
            return .failure(Refusal(unread))
        }
        return .success(Reading(route: .set, keepFirst: true))
    }

    /// `if s.insert(k).inserted { … r.append(x) … }` or `if !s.contains(k) { s.insert(k); … r.append(x) … }`,
    /// no else. `nil` when `ifExpression` is neither (the caller then classifies it).
    static func readSetBranch(
        _ ifExpression: IfExprSyntax, set: String, array: String, element: String
    ) -> Result<Reading, Refusal>? {
        guard ifExpression.elseBody == nil, let condition = singleCondition(ifExpression.conditions) else { return nil }
        let needsInsert: Bool
        if isInsertedCheck(condition, set: set) {
            needsInsert = false
        } else if let negation = condition.as(PrefixOperatorExprSyntax.self), negation.operator.text == "!",
                  let call = negation.expression.as(FunctionCallExprSyntax.self), isCall(call, on: set, named: "contains") {
            needsInsert = true
        } else {
            return nil
        }
        var inserted = false
        var appended = false
        for item in ifExpression.body.statements.map(\.item) {
            if isLet(item) { continue }
            if needsInsert, let call = item.as(FunctionCallExprSyntax.self), isCall(call, on: set, named: "insert") {
                inserted = true
                continue
            }
            if isAppend(item, array: array, element: element) {
                appended = true
                continue
            }
            return .failure(Refusal(unread))
        }
        guard appended, inserted || !needsInsert else { return .failure(Refusal(unread)) }
        return .success(Reading(route: .set, keepFirst: true))
    }

    static func readDictionaryLoop(_ body: CodeBlockSyntax, dictionary: String, element: String) -> Result<Reading, Refusal> {
        for item in body.statements.map(\.item) {
            if isLet(item) { continue }
            if isWrite(item, dictionary: dictionary, element: element) { continue }
            if let ifExpression = item.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self)
                ?? item.as(IfExprSyntax.self), ifExpression.elseBody == nil, isContinueOnly(ifExpression.body) {
                if readsKey(ifExpression.conditions, dictionary: dictionary) { continue }
                return .failure(Refusal(otherSkip))
            }
            if item.tokens(viewMode: .sourceAccurate).contains(where: { $0.tokenKind == .keyword(.continue) }) {
                return .failure(Refusal(otherSkip))
            }
            return .failure(Refusal(unread))
        }
        return .success(Reading(route: .dictionary, keepFirst: false))
    }

    /// `d[k] = x`, as the parser leaves it: an unfolded sequence `d[k]`, `=`, `x`.
    static func isWrite(_ item: CodeBlockItemSyntax.Item, dictionary: String, element: String) -> Bool {
        let expression = item.as(ExprSyntax.self)
        let elements: [ExprSyntax]
        if let sequence = expression?.as(SequenceExprSyntax.self) {
            elements = Array(sequence.elements)
        } else if let infix = expression?.as(InfixOperatorExprSyntax.self) {
            elements = [infix.leftOperand, infix.operator, infix.rightOperand]
        } else {
            return false
        }
        guard elements.count == 3, elements[1].is(AssignmentExprSyntax.self),
              let subscripted = elements[0].as(SubscriptCallExprSyntax.self),
              subscripted.calledExpression.trimmedDescription == dictionary, subscripted.arguments.count == 1 else {
            return false
        }
        return elements[2].trimmedDescription == element
    }

    /// Whether the condition reads `d[…]`.
    static func readsKey(_ conditions: ConditionElementListSyntax, dictionary: String) -> Bool {
        conditions.tokens(viewMode: .sourceAccurate).contains { token in
            guard token.text == dictionary, let reference = token.parent?.as(DeclReferenceExprSyntax.self) else {
                return false
            }
            return reference.parent?.as(SubscriptCallExprSyntax.self)?.calledExpression.id == reference.id
        }
    }
}
