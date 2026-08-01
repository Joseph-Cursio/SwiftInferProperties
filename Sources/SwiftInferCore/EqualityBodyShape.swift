import SwiftSyntax

/// What a hand-written `static func == ` actually *does*, read off its body.
///
/// ## Why this is the signal worth having
///
/// `fixtures/equatable-signal/README.md` set out to test whether an `Equatable`
/// conformance justifies a property test, and its measured conclusion names this
/// exact thing as the replacement: *"conformance does not predict refutability. What
/// predicts it is the **shape of the `==` body**, which is also syntactic and also
/// cheap."* Nothing read the body until now — `SequenceViewModelLawTemplate` shipped
/// using "declares a custom `==`" as a proxy for it, with the residual hazard written
/// into a caveat that asked the reader to go open the body themselves.
///
/// ## The three shapes, and the real bodies that define them
///
/// Taken from swift-collections, which is where the fixture's three measured
/// projection bugs live:
///
/// - **`Deque`** — a count guard, a referential fast path, then
///   `return left.elementsEqual(right)`. The result expression **is** the
///   sequence comparison, so a law of the form `(a == b) == a.elementsEqual(b)`
///   restates it and cannot fail on it.
/// - **`BitArray`** — `guard left._count == right._count else { return false }`
///   then `return left._storage == right._storage`. A **projection** onto two
///   stored fields, and the fixture's headline case: correct only while an
///   invariant `==` does not itself enforce keeps holding.
/// - **`OrderedSet`** — `left._elements == right._elements`. A projection onto one.
///
/// The guard's fields count toward the projection, because the answer genuinely
/// depends on them — `BitArray` reads `_count` and `_storage`, and reporting only
/// the latter would misdescribe what equality means for that type.
public enum EqualityBodyShape: Sendable, Equatable {

    /// The result expression is the element-wise sequence comparison —
    /// `left.elementsEqual(right)`, or `Array(left) == Array(right)`.
    ///
    /// Consumers stating a law *about* the sequence view must treat this as a
    /// refutability problem: the law reduces to `X == X` on everything but the
    /// guards.
    case sequenceComparison(callee: String)

    /// The result compares a subset of stored members — `lhs.a == rhs.a && …`.
    /// Member names in source order, deduplicated, guards included.
    ///
    /// **This is the refutable shape**, and the one three real bugs were found in.
    /// A projection is still an equivalence relation however wrong it is, so the
    /// `Equatable` laws pass and only a model law can see the defect.
    case storedFieldProjection(members: [String])

    /// The result compares two values through the same conversion —
    /// `Set(left) == Set(right)`. Every bit of information the conversion discards
    /// is information `==` has stopped distinguishing, which is exactly the
    /// fixture's `UnorderedMutantSet`.
    case conversionComparison(via: String)

    /// A body this classifier does not model. Never evidence for anything.
    case unclassified

    /// Conversions that preserve the element sequence, so `Array(a) == Array(b)` is
    /// the sequence comparison rather than a lossy conversion.
    static let sequencePreservingConversions: Set<String> = [
        "Array", "ContiguousArray", "ArraySlice"
    ]

    /// Sequence-comparison callees. Deliberately tiny: each is a stdlib method whose
    /// documented meaning is element-wise ordered comparison, so no type can
    /// reinterpret it. `starts(with:)` is absent on purpose — it is a prefix test.
    static let sequenceComparisonCallees: Set<String> = ["elementsEqual"]
}

/// Classifies an `==` body. Pure syntax, no semantic resolution.
public enum EqualityBodyClassifier {

    /// Classify `body` as the body of a `static func ==`.
    ///
    /// The method is deliberately structured around the **result expression** —
    /// the value the function actually returns — with early-outs treated as guards
    /// rather than as the answer. A `guard … else { return false }` narrows the
    /// domain; it is not what equality *means* for the type.
    public static func classify(
        body: CodeBlockSyntax,
        operands: [String] = []
    ) -> EqualityBodyShape {
        let statements = Array(body.statements)
        guard let resultExpression = resultExpression(of: statements) else {
            return .unclassified
        }

        if let callee = sequenceComparisonCallee(in: resultExpression) {
            return .sequenceComparison(callee: callee)
        }
        if let spelling = inlinedPairwiseScan(
            result: resultExpression, statements: statements, operands: operands
        ) {
            return .sequenceComparison(callee: spelling)
        }
        if let conversion = conversionComparison(in: resultExpression) {
            return EqualityBodyShape.sequencePreservingConversions.contains(conversion)
                ? .sequenceComparison(callee: conversion)
                : .conversionComparison(via: conversion)
        }

        // Guards contribute to the projection: BitArray's equality genuinely depends
        // on `_count` as well as `_storage`.
        var members = statements.dropLast().flatMap { comparedMembers(in: $0) }
        members.append(contentsOf: comparedMemberNames(in: resultExpression))
        let unique = deduplicated(members)
        return unique.isEmpty ? .unclassified : .storedFieldProjection(members: unique)
    }

    // MARK: - Locating the answer

    /// The expression whose value the function returns: an explicit trailing
    /// `return X`, or a bare expression under Swift's implicit return.
    private static func resultExpression(of statements: [CodeBlockItemSyntax]) -> ExprSyntax? {
        guard let last = statements.last else { return nil }
        switch last.item {
        case .stmt(let statement):
            return statement.as(ReturnStmtSyntax.self)?.expression

        case .expr(let expression):
            return expression

        case .decl:
            return nil
        }
    }

    // MARK: - Shape probes

    /// `elementsEqual` written out by hand — the shape that admits equality only by
    /// **exhausting both operands** without finding a difference.
    ///
    /// Returns the spelling found, for the explainability line.
    ///
    /// **Both extensions here were found by reading the classifier's own output, not
    /// by design**, which is the argument for running a new signal over a corpus
    /// before trusting it. The first version keyed on `elementsEqual` alone and
    /// classified `Array`, `ContiguousArray` and `ArraySlice` as `.unclassified` —
    /// three of the seven carriers this signal exists to score. Reading them shows
    /// two more spellings of one idea:
    ///
    ///     // Array.swift:2007 — indexed
    ///     for idx in 0..<lhsCount { if lhs[idx] != rhs[idx] { return false } }
    ///     return true
    ///
    ///     // ArraySlice.swift:1466 — parallel iterators
    ///     var streamLHS = lhs.makeIterator(); var streamRHS = rhs.makeIterator()
    ///     while nextLHS != nil { … if nextLHS != nextRHS { return false } … }
    ///     return true
    ///
    /// The invariant both share, and the one this keys on, is that `true` is reached
    /// only by falling out of a loop that returns `false` on any difference. A guard
    /// or fast path that returns `true` early does not qualify — those are the
    /// *preconditions* of the comparison, not the comparison.
    private static func inlinedPairwiseScan(
        result: ExprSyntax,
        statements: [CodeBlockItemSyntax],
        operands: [String]
    ) -> String? {
        guard let literal = result.as(BooleanLiteralExprSyntax.self),
              literal.literal.tokenKind == .keyword(.true) else {
            return nil
        }
        let preceding = statements.dropLast()
        guard let loop = preceding.compactMap(loopBody(of:)).first(where: returnsFalse) else {
            return nil
        }
        if preceding.contains(where: iteratesAZipOfBoth) { return "zip traversal" }
        // Both operands must take part, or this is a scan over one of them and says
        // nothing about the pair.
        guard operands.isEmpty || operands.allSatisfy({ name in
            preceding.contains { $0.description.contains(name) }
        }) else {
            return nil
        }
        // A scan is PAIRWISE only if it walks both operands in lockstep. The
        // rejected alternative is a membership scan — iterate one operand and
        // SEARCH the other — which is deliberately order-INsensitive and is the
        // opposite of what this case means.
        //
        // `OrderedSet.UnorderedView.==` is the witness that forced this, and it was
        // a false positive of the looser rule:
        //
        //     for item in left._base { if !right._base.contains(item) { return false } }
        //     return true
        //
        // Result `true`, a loop returning `false`, both operands mentioned — it
        // satisfied every condition above while meaning the reverse.
        if comparesTwoSubscripts(loop) { return "inlined element loop" }
        if drawsFromTwoIterators(preceding) { return "inlined pairwise scan" }
        return nil
    }

    /// Whether a statement is `for … in zip(a, b)`.
    ///
    /// **The fourth spelling, and the one that was missed.** `zip` is lockstep by
    /// definition, so this is the least ambiguous pairwise traversal of the four —
    /// and the tightening that removed the membership-scan false positives took it
    /// out along with them, because it uses neither subscripts nor `makeIterator`:
    ///
    ///     // SortedSet+Equatable.swift:27
    ///     for (k1, k2) in zip(lhs, rhs) { if k1 != k2 { return false } }
    ///     return true
    ///
    /// Recorded because the loss was invisible from inside the classifier: the
    /// tightening was validated by checking that the false positives had gone, not by
    /// checking what else went with them. "Measure after each fix" applies to the
    /// things a fix removes, not only to the ones it was aimed at.
    private static func iteratesAZipOfBoth(_ item: CodeBlockItemSyntax) -> Bool {
        guard case .stmt(let statement) = item.item,
              let loop = statement.as(ForStmtSyntax.self),
              let call = loop.sequence.as(FunctionCallExprSyntax.self),
              let callee = call.calledExpression.as(DeclReferenceExprSyntax.self),
              callee.baseName.text == "zip" else {
            return false
        }
        return call.arguments.count == 2
    }

    /// Whether the statements draw from two independent iterators — the parallel-
    /// traversal spelling `ArraySlice` uses.
    private static func drawsFromTwoIterators(
        _ statements: ArraySlice<CodeBlockItemSyntax>
    ) -> Bool {
        final class Collector: SyntaxVisitor {

            var iteratorFactories = 0

            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                if let member = node.calledExpression.as(MemberAccessExprSyntax.self),
                   member.declName.baseName.text == "makeIterator" {
                    iteratorFactories += 1
                }
                return .visitChildren
            }
        }
        let collector = Collector(viewMode: .sourceAccurate)
        for item in statements { collector.walk(item) }
        return collector.iteratorFactories >= 2
    }

    /// The body of a `for` / `while` / `repeat` statement, or `nil`.
    private static func loopBody(of item: CodeBlockItemSyntax) -> CodeBlockSyntax? {
        guard case .stmt(let statement) = item.item else { return nil }
        if let loop = statement.as(ForStmtSyntax.self) { return loop.body }
        if let loop = statement.as(WhileStmtSyntax.self) { return loop.body }
        if let loop = statement.as(RepeatStmtSyntax.self) { return loop.body }
        return nil
    }

    /// Whether `block` contains a `return false` — the bail-out that makes a scan a
    /// comparison rather than a fold.
    private static func returnsFalse(_ block: CodeBlockSyntax) -> Bool {
        final class Collector: SyntaxVisitor {

            var found = false

            override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind {
                if let literal = node.expression?.as(BooleanLiteralExprSyntax.self),
                   literal.literal.tokenKind == .keyword(.false) {
                    found = true
                }
                return .visitChildren
            }
        }
        let collector = Collector(viewMode: .sourceAccurate)
        collector.walk(block)
        return collector.found
    }

    /// Whether `block` compares two subscript expressions to each other.
    private static func comparesTwoSubscripts(_ block: CodeBlockSyntax) -> Bool {
        final class Collector: SyntaxVisitor {

            var subscripts = 0

            override func visit(_: SubscriptCallExprSyntax) -> SyntaxVisitorContinueKind {
                subscripts += 1
                return .visitChildren
            }
        }
        let collector = Collector(viewMode: .sourceAccurate)
        collector.walk(block)
        return collector.subscripts >= 2
    }

    /// The callee name when `expression` is (or contains, at its top level) a
    /// sequence comparison.
    private static func sequenceComparisonCallee(in expression: ExprSyntax) -> String? {
        for call in functionCalls(in: expression) {
            guard let member = call.calledExpression.as(MemberAccessExprSyntax.self) else { continue }
            let name = member.declName.baseName.text
            if EqualityBodyShape.sequenceComparisonCallees.contains(name) {
                return name
            }
        }
        return nil
    }

    /// The conversion name when the expression is `F(lhs) == F(rhs)` for one `F`.
    private static func conversionComparison(in expression: ExprSyntax) -> String? {
        let calls = functionCalls(in: expression).compactMap { call -> String? in
            call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
        }
        guard calls.count == 2, calls[0] == calls[1] else { return nil }
        // A bare `Foo(x)` on both sides only reads as a conversion if the operator
        // between them is an equality test.
        guard operators(in: expression).contains("==") else { return nil }
        return calls[0]
    }

    /// Member names compared in a guard / if early-out.
    private static func comparedMembers(in item: CodeBlockItemSyntax) -> [String] {
        guard case .stmt(let statement) = item.item else { return [] }
        if let guardStatement = statement.as(GuardStmtSyntax.self) {
            return guardStatement.conditions.flatMap { condition -> [String] in
                guard case .expression(let expression) = condition.condition else { return [] }
                return comparedMemberNames(in: expression)
            }
        }
        return []
    }

    /// Names of member accesses joined by `==` / `&&` / `!=` in `expression`.
    ///
    /// Returns empty when any other operator appears, so `lhs.a < rhs.a` — the
    /// ordering leak the fixture's `OrderedLeakPair` reproduces — is not reported as
    /// an equality projection.
    private static func comparedMemberNames(in expression: ExprSyntax) -> [String] {
        let allowed: Set<String> = ["==", "&&", "!="]
        let found = operators(in: expression)
        guard !found.isEmpty, found.isSubset(of: allowed) else { return [] }
        return memberAccesses(in: expression)
    }

    // MARK: - Syntax walking

    /// Operator tokens at any depth of `expression`.
    private static func operators(in expression: ExprSyntax) -> Set<String> {
        final class Collector: SyntaxVisitor {

            var found: Set<String> = []

            override func visit(_ node: BinaryOperatorExprSyntax) -> SyntaxVisitorContinueKind {
                found.insert(node.operator.text)
                return .visitChildren
            }
        }
        let collector = Collector(viewMode: .sourceAccurate)
        collector.walk(expression)
        return collector.found
    }

    /// Member-access names whose base is a plain identifier — `left._storage` yields
    /// `_storage`, while a chained `left.a.b` is skipped as not a bare field compare.
    private static func memberAccesses(in expression: ExprSyntax) -> [String] {
        final class Collector: SyntaxVisitor {

            var found: [String] = []

            override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
                if node.base?.is(DeclReferenceExprSyntax.self) == true {
                    found.append(node.declName.baseName.text)
                }
                return .visitChildren
            }
        }
        let collector = Collector(viewMode: .sourceAccurate)
        collector.walk(expression)
        return collector.found
    }

    private static func functionCalls(in expression: ExprSyntax) -> [FunctionCallExprSyntax] {
        final class Collector: SyntaxVisitor {

            var found: [FunctionCallExprSyntax] = []

            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                found.append(node)
                return .visitChildren
            }
        }
        let collector = Collector(viewMode: .sourceAccurate)
        collector.walk(expression)
        return collector.found
    }

    /// Order-preserving deduplication, so the reported member list is stable.
    private static func deduplicated(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.filter { seen.insert($0).inserted }
    }
}
