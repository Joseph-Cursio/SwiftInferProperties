import SwiftSyntax

/// Reads #669's criteria 2 and 3 off a function body (SwiftInferProperties#692): a candidate tested
/// against names already issued, decorated on a hit, and written back.
///
/// ```swift
/// func uniqName(item: SyntaxStructure, relationship: String) -> String {
///     guard let name = item.fullName else { return "" }
///     var newName = name
///     if uniqElementNames.contains(name) {
///         repeat {
///             newName = name + "\(index)"
///             index += 1
///         } while takenIdentifiers.contains(newName)
///     } else {
///         uniqElementNames.append(name)
///     }
///     return newName
/// }
/// ```
///
/// reads TEST (`uniqElementNames.contains`), TIED (`"\(index)"` in the span that test decides, built into
/// what is returned) and WRITE (`uniqElementNames.append`), with the sentinel `""`.
///
/// It is a syntax-tree port of the census's cues, frozen in `docs/plans/uniquifier-law-census-scope.md`
/// §1.2 and run as `scripts/uniquifier_census.py`. Applied there as a gate, they admitted 9 decision rows,
/// and 8 owed the law. The census read text; this reads the tree, so a span a test decides is an `if`,
/// `while`, `guard`, `repeat` or ternary node rather than a brace count.
public enum UniquifierShapeReader {
    /// The shape, or `nil` unless TEST ∧ (TIED ∨ RETEST) ∧ WRITE hold.
    public static func read(_ function: FunctionDeclSyntax) -> UniquifierShape? {
        guard let body = UniquifierBody(function: function) else { return nil }
        let tests = body.membershipTests()
        guard let firstTest = tests.first else { return nil }
        let facts = body.counters()
        let spans = body.decidedSpans(tests)
        let tied = body.decorations(facts).filter { body.isTied($0, tests: tests, spans: spans, facts: facts) }
        let retests = body.retests(tests)
        guard !tied.isEmpty || !retests.isEmpty, let write = writeNode(body, tests, facts) else { return nil }
        let converter = SourceLocationConverter(fileName: "", tree: function.root)
        func line(_ node: some SyntaxProtocol) -> Int {
            node.startLocation(converter: converter).line
        }
        let testedBases = Set(tests.map(\.base)).filter(body.isStored)
        return UniquifierShape(
            testedBases: testedBases.sorted(),
            testedChains: Set(tests.map(\.chain)).filter { body.isStored(UniquifierBody.base(of: $0)) }.sorted(),
            decoration: decoration(tied: tied, retests: retests, body: body),
            sentinel: sentinel(of: body),
            isMemoizing: isMemoizing(body, testedBases: testedBases),
            testLine: line(firstTest.node),
            decorationLine: tied.first.map { line($0.node) } ?? retests.first.map { line($0.body) } ?? 0,
            writeLine: line(write)
        )
    }

    /// `[T]`, `Array`, `Set`, `Dictionary`, `OrderedSet`, `OrderedDictionary` or `ContiguousArray`: a type an
    /// `inout` parameter can carry a uniquifier's state in.
    public static func isCollectionType(_ type: String) -> Bool {
        let kind = type.drop { $0 == " " }
        if kind.hasPrefix("["), kind.hasSuffix("]") { return true }
        let head = kind.prefix { $0 != "<" && $0 != " " }
        return UniquifierBody.collectionTypes.contains(String(head.split(separator: ".").last ?? head))
    }

    /// The stored state `function` writes and removes from.
    public static func stateWrites(of function: FunctionDeclSyntax) -> StateWrites {
        UniquifierBody(function: function)?.stateWrites() ?? .empty
    }

    /// WRITE: a stored tested base the body writes, an `.inserted` test on a stored base, or an incremented
    /// stored counter.
    private static func writeNode(
        _ body: UniquifierBody,
        _ tests: [MembershipTest],
        _ facts: UniquifierCounters
    ) -> Syntax? {
        for base in Set(tests.map(\.base)).sorted() where body.isStored(base) {
            if let write = body.firstWrite(of: base) { return write }
        }
        if let inserted = tests.first(where: { $0.kind == .inserted && body.isStored($0.base) }) {
            return inserted.node
        }
        return body.nodes.first { node in
            guard let elements = node.as(SequenceExprSyntax.self).map({ Array($0.elements) }),
                  let chain = UniquifierBody.incrementedChain(elements) else {
                return false
            }
            return facts.storedIncrements.contains(chain)
        }
    }

    /// The tied decoration's spelling, or the text a re-test loop appends.
    private static func decoration(
        tied: [CounterDecoration],
        retests: [(chain: String, body: CodeBlockSyntax)],
        body: UniquifierBody
    ) -> UniquifierDecoration {
        if let first = tied.first { return .counter(prefix: first.prefix) }
        guard let loop = retests.first?.body else { return .counter(prefix: "") }
        let appended = body.nodes.lazy
            .filter { UniquifierBody.isInside($0, loop) }
            .compactMap { $0.as(StringLiteralExprSyntax.self) }
            .first { literal in literal.segments.allSatisfy { if case .stringSegment = $0 { true } else { false } } }
        guard let text = appended?.segments.trimmedDescription, !text.isEmpty else { return .counter(prefix: "") }
        return .appended(text)
    }

    /// What a leading `guard … else { return <literal> }` returns: `""` or `nil`.
    private static func sentinel(of body: UniquifierBody) -> String? {
        guard let guarded = body.statements.first?.item.as(GuardStmtSyntax.self),
              let returned = guarded.body.statements.lazy
                  .compactMap({ $0.item.as(ReturnStmtSyntax.self)?.expression }).first else {
            return nil
        }
        if returned.is(NilLiteralExprSyntax.self) { return "nil" }
        guard let literal = returned.as(StringLiteralExprSyntax.self),
              literal.segments.allSatisfy({ if case .stringSegment = $0 { true } else { false } }) else {
            return nil
        }
        return literal.trimmedDescription
    }

    /// `if let id = byKey[key] { return id }` on a tested base: a stored id returned for a seen key, bare or
    /// inside what is returned.
    private static func isMemoizing(_ body: UniquifierBody, testedBases: Set<String>) -> Bool {
        body.nodes.contains { node in
            guard let branch = node.as(IfExprSyntax.self) else { return false }
            for condition in branch.conditions {
                guard let binding = condition.condition.as(OptionalBindingConditionSyntax.self),
                      let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let value = binding.initializer?.value,
                      let access = (value.as(ForceUnwrapExprSyntax.self)?.expression ?? value)
                          .as(SubscriptCallExprSyntax.self),
                      let table = UniquifierBody.chain(access.calledExpression).map(UniquifierBody.base(of:)),
                      testedBases.contains(table) else {
                    continue
                }
                // `return id`, or the id inside what is returned: `return "\"\(id)\""`.
                let returnsBinding = branch.body.statements.contains { statement in
                    guard let returned = statement.item.as(ReturnStmtSyntax.self)?.expression else { return false }
                    return UniquifierBody.freeNames(in: returned).contains(name)
                }
                if returnsBinding { return true }
            }
            return false
        }
    }
}
