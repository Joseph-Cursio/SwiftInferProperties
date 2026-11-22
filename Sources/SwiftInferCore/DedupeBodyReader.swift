import SwiftSyntax

/// #671's body gate (SwiftInferProperties#711): whether a recognised dedupe keeps one element per
/// key, read off its body so the count laws are owed rather than guessed from the name.
///
/// ```swift
/// static func dedupe(relationships: [ERRelationship]) -> [ERRelationship] {
///     var seen: Set<String> = []
///     var result: [ERRelationship] = []
///     for relationship in relationships {
///         let key = …
///         if !seen.contains(key) {
///             seen.insert(key)
///             result.append(relationship)
///         }
///     }
///     return result
/// }
/// ```
///
/// reads the Set route: every element whose key is new reaches the result, and nothing else does.
///
/// **Written from the frozen scope, not copied from the census harness.** The rules are
/// `docs/plans/dedupe-count-law-census-scope.md` §2.4, plus the two forms #711 adds, which the census
/// found refused: `seen.insert(k).0`, and a `for … where` clause that does the insert or the
/// `!contains` test. The scope's §4 controls are this reader's tests.
///
/// **Only the names a template already proposes are read** (`dedupe`, `deduplicate`,
/// `deduplicated`). Widening the vocabulary is out of scope: the census's only widened emittable
/// row is one function, and one row cannot decide a vocabulary change.
///
/// **Only the parameter form.** A receiver form (`extension Array { func deduplicated() … }`) is
/// over an unconstrained `Element`, so no stub can draw it (#493), and the census found none it
/// could emit.
public enum DedupeBodyReader {

    /// What the reader concluded about a function in the name family and of the right shape.
    public enum Reading: Equatable, Sendable {
        case admitted(DedupeBody)
        /// Refused, with the first reason found: one of the `Refusal` constants.
        case refused(String)
    }

    /// The scope's refusal reasons, spelled as the census spelled them.
    public enum Refusal {
        /// Neither route's local: the body keeps no record of the keys it has seen.
        public static let noLocal = "body: no set or dictionary local"
        /// An element can reach the result without its key being new: a pass-through or an extra append.
        public static let appendNotBehindInsert = "body: append not behind an insert"
        /// A `return` other than the final statement, which can skip the dedupe entirely.
        public static let earlyReturn = "body: early return"
        /// A `continue`, `break` or `where` that skips for a reason other than key presence: a filter.
        public static let otherSkip = "body: other skip"
        /// Any other statement or shape the scope does not admit.
        public static let unread = "body: unread form"
    }

    /// The names whose rows the body gate decides: the ones `IdempotenceTemplate` recognises today.
    public static let recognisedNames: Set<String> = ["dedupe", "deduplicate", "deduplicated"]

    /// A first label that hands the function a key to dedupe by, which the count laws cannot supply.
    static let keyClosureLabels: Set<String> = ["on", "by", "using", "keyPath"]

    /// The route, or `nil` when the function is not an admitted dedupe.
    public static func read(_ function: FunctionDeclSyntax) -> DedupeBody? {
        guard case .admitted(let body) = reading(of: function) else { return nil }
        return body
    }

    /// The reading, or `nil` when the name or the shape puts the function outside the gate.
    public static func reading(of function: FunctionDeclSyntax) -> Reading? {
        guard recognisedNames.contains(function.name.text), let input = inputName(of: function) else {
            return nil
        }
        guard let body = function.body else { return .refused(Refusal.unread) }
        return reading(of: body, input: input)
    }

    /// The parameter a `[T] -> [T]` dedupe reads, or `nil` when the shape is anything else.
    ///
    /// Synchronous, non-throwing and non-mutating; exactly one parameter, an array of the element
    /// the function returns an array of, with no `inout` or ownership specifier and no key label.
    static func inputName(of function: FunctionDeclSyntax) -> String? {
        let signature = function.signature
        guard signature.effectSpecifiers?.asyncSpecifier == nil,
              signature.effectSpecifiers?.throwsClause == nil,
              !function.modifiers.contains(where: { $0.name.tokenKind == .keyword(.mutating) }),
              let returned = signature.returnClause.flatMap({ element(of: $0.type) }),
              signature.parameterClause.parameters.count == 1,
              let parameter = signature.parameterClause.parameters.first,
              !parameter.type.is(AttributedTypeSyntax.self),
              element(of: parameter.type) == returned,
              !keyClosureLabels.contains(parameter.firstName.text) else {
            return nil
        }
        return (parameter.secondName ?? parameter.firstName).text
    }

    /// The element type of `[T]` or `Array<T>`, as written.
    static func element(of type: TypeSyntax) -> String? {
        if let array = type.as(ArrayTypeSyntax.self) { return array.element.trimmedDescription }
        guard let identifier = type.as(IdentifierTypeSyntax.self), identifier.name.text == "Array",
              let arguments = identifier.genericArgumentClause?.arguments, arguments.count == 1 else {
            return nil
        }
        return arguments.first?.argument.trimmedDescription
    }

    /// The scope's two routes over a body whose input is `input`.
    static func reading(of body: CodeBlockSyntax, input: String) -> Reading {
        let items = body.statements.map(\.item)
        guard let last = items.last else { return .refused(Refusal.noLocal) }
        let returns = DedupeReturnCollector(viewMode: .sourceAccurate)
        returns.walk(body)
        if returns.found.contains(where: { $0.id != last.as(ReturnStmtSyntax.self)?.id }) {
            return .refused(Refusal.earlyReturn)
        }
        let locals = Locals(items.dropLast())
        guard !locals.sets.isEmpty || !locals.dictionaries.isEmpty else { return .refused(Refusal.noLocal) }
        let returned = last.as(ReturnStmtSyntax.self)?.expression
        if items.count == 2, locals.sets.count == 1, let filtered = returned?.as(FunctionCallExprSyntax.self),
           let callee = filtered.calledExpression.as(MemberAccessExprSyntax.self),
           callee.declName.baseName.text == "filter" {
            return readFilter(filtered, base: callee.base, input: input, set: locals.sets[0])
        }
        return readLoopForm(items: items, locals: locals, returned: returned, input: input)
    }

    /// The filter form: `return in.filter { s.insert(k).inserted }`, the insert the closure's sole
    /// expression.
    static func readFilter(
        _ call: FunctionCallExprSyntax, base: ExprSyntax?, input: String, set: String
    ) -> Reading {
        let closure = call.trailingClosure ?? call.arguments.first?.expression.as(ClosureExprSyntax.self)
        let argumentCount = call.trailingClosure == nil ? 1 : 0
        guard base?.trimmedDescription == input, call.arguments.count == argumentCount,
              let closure, closure.statements.count == 1,
              let only = closure.statements.first?.item.as(ExprSyntax.self),
              insertedKey(only, set: set) != nil else {
            return .refused(Refusal.unread)
        }
        return .admitted(DedupeBody(route: .set))
    }

    /// The loop forms: the locals, exactly one `for x in in` loop, and the final return.
    static func readLoopForm(
        items: [CodeBlockItemSyntax.Item], locals: Locals, returned: ExprSyntax?, input: String
    ) -> Reading {
        let middle = items.dropLast()
        let loops = middle.compactMap { $0.as(ForStmtSyntax.self) }
        guard loops.count == 1, let loop = loops.first, loop.sequence.trimmedDescription == input,
              loop.tryKeyword == nil, loop.awaitKeyword == nil,
              let element = loop.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
            return .refused(Refusal.unread)
        }
        for item in middle where !item.is(ForStmtSyntax.self) && Locals.local(item) == nil {
            let appended = locals.arrays.contains { appends(to: $0, in: item) }
            return .refused(appended ? Refusal.appendNotBehindInsert : Refusal.unread)
        }
        let returnedText = returned?.trimmedDescription
        if locals.sets.count == 1, locals.arrays.count == 1, locals.dictionaries.isEmpty,
           returnedText == locals.arrays[0] {
            return SetLoop(set: locals.sets[0], array: locals.arrays[0], element: element).read(loop)
        }
        if locals.dictionaries.count == 1, locals.sets.isEmpty, locals.arrays.isEmpty,
           returnedText == "Array(\(locals.dictionaries[0]).values)" {
            return DictionaryLoop(dictionary: locals.dictionaries[0], element: element).read(loop)
        }
        return .refused(Refusal.unread)
    }

    /// The key of `s.insert(k).inserted` or `s.insert(k).0`, or `nil` when `expression` is neither.
    static func insertedKey(_ expression: ExprSyntax, set: String) -> String? {
        guard let member = expression.as(MemberAccessExprSyntax.self),
              ["inserted", "0"].contains(member.declName.baseName.text),
              let call = member.base?.as(FunctionCallExprSyntax.self) else {
            return nil
        }
        return argument(of: call, on: set, named: "insert")
    }

    /// The key of `!s.contains(k)`, or `nil` when `expression` is not that test.
    static func absentKey(_ expression: ExprSyntax, set: String) -> String? {
        guard let negation = expression.as(PrefixOperatorExprSyntax.self), negation.operator.text == "!",
              let call = negation.expression.as(FunctionCallExprSyntax.self) else {
            return nil
        }
        return argument(of: call, on: set, named: "contains")
    }

    /// The sole unlabelled argument's text when `call` is `base.name(_:)`, or `nil`.
    static func argument(of call: FunctionCallExprSyntax, on base: String, named name: String) -> String? {
        guard let callee = call.calledExpression.as(MemberAccessExprSyntax.self),
              callee.base?.trimmedDescription == base, callee.declName.baseName.text == name,
              call.arguments.count == 1, call.trailingClosure == nil,
              let only = call.arguments.first, only.label == nil else {
            return nil
        }
        return only.expression.trimmedDescription
    }

    /// Whether any `array.append` occurs anywhere in `node`.
    static func appends(to array: String, in node: some SyntaxProtocol) -> Bool {
        node.tokens(viewMode: .sourceAccurate).contains { token in
            guard token.text == "append",
                  let member = token.parent?.parent?.as(MemberAccessExprSyntax.self) else { return false }
            return member.base?.trimmedDescription == array
        }
    }

    /// Whether a `continue` or `break` occurs anywhere in `node`: a skip.
    static func skips(_ node: some SyntaxProtocol) -> Bool {
        node.tokens(viewMode: .sourceAccurate).contains {
            $0.tokenKind == .keyword(.continue) || $0.tokenKind == .keyword(.break)
        }
    }
}
