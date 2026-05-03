import SwiftInferCore
import SwiftSyntax

/// PRD §7.3 "Assert-Reduce-Equivalence → associativity" detector. Runs
/// against a `SlicedTestBody` looking for the assertion shape that
/// claims a reduce operation produces the same result regardless of
/// element order: `xs.reduce(seed, op) == xs.reversed().reduce(seed, op)`.
/// Equivalence under `.reversed()` is the property tests' standard
/// witness for the reducer `op` being associative + commutative
/// (combined: a commutative monoid). The +20 cross-validation signal
/// lights up `AssociativityTemplate` for the matching `op` callee.
///
/// **Recognized shapes:**
/// - **Collapsed** (one assertion line):
///   ```
///   XCTAssertEqual(xs.reduce(0, +), xs.reversed().reduce(0, +))
///   #expect(items.reduce(.zero, combine) == items.reversed().reduce(.zero, combine))
///   ```
/// - **Explicit** (two-binding):
///   ```
///   let lhs = xs.reduce(0, +)
///   let rhs = xs.reversed().reduce(0, +)
///   XCTAssertEqual(lhs, rhs)
///   ```
///
/// **Method-chain `xs.reduce(_:_:)` only.** M5 plan OD #3 default
/// scopes reordering to `.reversed()`; arbitrary-permutation reduce
/// equivalence (`xs.shuffled().reduce(...)`, `xs.permutations.allSatisfy`)
/// is M7 counter-signal territory. Both sides must call `.reduce` as a
/// member-access chain with exactly two unlabeled arguments.
///
/// **Asymmetric `.reversed()` shape.** Exactly one side is `<base>.reduce(...)`
/// (direct), the other is `<base>.reversed().reduce(...)` (reversed).
/// Both-direct (tautology) and both-reversed (also tautology) shapes
/// reject. The collection identifier on both sides must match (`xs` /
/// `xs`).
///
/// **Same-`op` invariant.** Textual equality on the second argument
/// expression. `xs.reduce(0, +) == xs.reversed().reduce(0, *)` rejects.
/// **Same-seed invariant.** Textual equality on the first argument
/// expression. `xs.reduce(0, +) == xs.reversed().reduce(1, +)` rejects.
///
/// **Op shape: `DeclReferenceExprSyntax` only.** Operator (`+`, `*`)
/// and bare-identifier (`combine`) callees both surface; closures and
/// member-access ops (`pricing.combine`) are deferred.
public enum AssertReduceEquivalenceDetector {

    public static func detect(in slice: SlicedTestBody) -> [DetectedReduceEquivalence] {
        guard let assertion = slice.assertion else {
            return []
        }
        if let collapsed = detectCollapsed(assertion: assertion) {
            return [collapsed]
        }
        if let explicit = detectExplicit(assertion: assertion, propertyRegion: slice.propertyRegion) {
            return [explicit]
        }
        return []
    }

    // MARK: - Collapsed shape

    private static func detectCollapsed(assertion: AssertionInvocation) -> DetectedReduceEquivalence? {
        switch assertion.kind {
        case .xctAssertEqual:
            return collapsedFromTwoArguments(
                lhs: assertion.arguments.first,
                rhs: assertion.arguments.dropFirst().first,
                location: assertion.location
            )
        case .expectMacro:
            guard let firstArg = assertion.arguments.first else {
                return nil
            }
            return collapsedFromEqualityExpression(firstArg, location: assertion.location)
        case .xctAssertTrue, .xctAssert, .xctAssertNotNil,
                .xctAssertLessThan, .xctAssertLessThanOrEqual, .requireMacro:
            return nil
        }
    }

    private static func collapsedFromTwoArguments(
        lhs: ExprSyntax?,
        rhs: ExprSyntax?,
        location: SwiftInferCore.SourceLocation
    ) -> DetectedReduceEquivalence? {
        guard let lhs, let rhs else {
            return nil
        }
        if let detected = matchedReduceEquivalence(lhs: lhs, rhs: rhs, location: location) {
            return detected
        }
        return matchedReduceEquivalence(lhs: rhs, rhs: lhs, location: location)
    }

    private static func collapsedFromEqualityExpression(
        _ expr: ExprSyntax,
        location: SwiftInferCore.SourceLocation
    ) -> DetectedReduceEquivalence? {
        if let sequence = expr.as(SequenceExprSyntax.self),
           let pair = equalityPair(in: sequence) {
            return collapsedFromTwoArguments(lhs: pair.lhs, rhs: pair.rhs, location: location)
        }
        if let infix = expr.as(InfixOperatorExprSyntax.self),
           let opExpr = infix.operator.as(BinaryOperatorExprSyntax.self),
           opExpr.operator.text == "==" {
            return collapsedFromTwoArguments(
                lhs: infix.leftOperand,
                rhs: infix.rightOperand,
                location: location
            )
        }
        return nil
    }

    private struct EqualityPair {
        let lhs: ExprSyntax
        let rhs: ExprSyntax
    }

    private static func equalityPair(in sequence: SequenceExprSyntax) -> EqualityPair? {
        let elements = Array(sequence.elements)
        guard elements.count == 3,
              let opExpr = elements[1].as(BinaryOperatorExprSyntax.self),
              opExpr.operator.text == "==" else {
            return nil
        }
        return EqualityPair(lhs: elements[0], rhs: elements[2])
    }

    // MARK: - Reduce-shape parsing + matching

    /// One side of the assertion, parsed as `<base>.reduce(seed, op)` —
    /// `base` is either a bare DeclRef (direct shape) or a
    /// `<DeclRef>.reversed()` call (reversed shape).
    private struct ReduceShape {
        let collectionName: String
        let seedSource: String
        let opCalleeName: String
        let isReversed: Bool
    }

    /// Parse `<base>.reduce(seed, op)`. Returns nil for any non-reduce
    /// shape, member chains beyond the `.reversed()` single hop, calls
    /// with arg counts ≠ 2, labeled args, or non-DeclRef ops.
    private static func parseReduce(_ expr: ExprSyntax) -> ReduceShape? {
        guard let call = expr.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "reduce",
              call.arguments.count == 2,
              let base = member.base else {
            return nil
        }
        let argList = Array(call.arguments)
        let seedExpr = argList[0]
        let opExpr = argList[1]
        guard seedExpr.label == nil,
              opExpr.label == nil,
              let opRef = opExpr.expression.as(DeclReferenceExprSyntax.self) else {
            return nil
        }
        let collectionName: String
        let isReversed: Bool
        if let directRef = base.as(DeclReferenceExprSyntax.self) {
            collectionName = directRef.baseName.text
            isReversed = false
        } else if let reversedShape = parseReversedBase(base) {
            collectionName = reversedShape
            isReversed = true
        } else {
            return nil
        }
        return ReduceShape(
            collectionName: collectionName,
            seedSource: seedExpr.expression.trimmedDescription,
            opCalleeName: opRef.baseName.text,
            isReversed: isReversed
        )
    }

    /// Return the bare collection identifier inside `<DeclRef>.reversed()`.
    /// Nil for any other shape.
    private static func parseReversedBase(_ base: ExprSyntax) -> String? {
        guard let reversedCall = base.as(FunctionCallExprSyntax.self),
              let reversedMember = reversedCall.calledExpression.as(MemberAccessExprSyntax.self),
              reversedMember.declName.baseName.text == "reversed",
              reversedCall.arguments.isEmpty,
              let reversedBaseRef = reversedMember.base?.as(DeclReferenceExprSyntax.self) else {
            return nil
        }
        return reversedBaseRef.baseName.text
    }

    /// Try to interpret `lhs` as the direct reduce and `rhs` as the
    /// reversed reduce. Caller flips `lhs`/`rhs` for the swap orientation.
    private static func matchedReduceEquivalence(
        lhs: ExprSyntax,
        rhs: ExprSyntax,
        location: SwiftInferCore.SourceLocation
    ) -> DetectedReduceEquivalence? {
        guard let directShape = parseReduce(lhs),
              let reversedShape = parseReduce(rhs),
              !directShape.isReversed,
              reversedShape.isReversed,
              directShape.collectionName == reversedShape.collectionName,
              directShape.seedSource == reversedShape.seedSource,
              directShape.opCalleeName == reversedShape.opCalleeName else {
            return nil
        }
        return DetectedReduceEquivalence(
            opCalleeName: directShape.opCalleeName,
            seedSource: directShape.seedSource,
            collectionBindingName: directShape.collectionName,
            assertionLocation: location
        )
    }

    // MARK: - Explicit shape

    /// `let lhs = xs.reduce(...); let rhs = xs.reversed().reduce(...);
    /// XCTAssertEqual(lhs, rhs)` — three-statement shape.
    private static func detectExplicit(
        assertion: AssertionInvocation,
        propertyRegion: [CodeBlockItemSyntax]
    ) -> DetectedReduceEquivalence? {
        guard assertion.kind == .xctAssertEqual,
              assertion.arguments.count == 2,
              let lhsRef = assertion.arguments[0].as(DeclReferenceExprSyntax.self),
              let rhsRef = assertion.arguments[1].as(DeclReferenceExprSyntax.self) else {
            return nil
        }
        let bindings = collectBindings(in: propertyRegion)
        guard let lhsInit = bindings[lhsRef.baseName.text],
              let rhsInit = bindings[rhsRef.baseName.text] else {
            return nil
        }
        if let detected = matchedReduceEquivalence(lhs: lhsInit, rhs: rhsInit, location: assertion.location) {
            return detected
        }
        return matchedReduceEquivalence(lhs: rhsInit, rhs: lhsInit, location: assertion.location)
    }

    // MARK: - Helpers

    private static func collectBindings(
        in items: [CodeBlockItemSyntax]
    ) -> [String: ExprSyntax] {
        var bindings: [String: ExprSyntax] = [:]
        for item in items {
            guard case .decl(let decl) = item.item,
                  let varDecl = decl.as(VariableDeclSyntax.self),
                  let firstBinding = varDecl.bindings.first,
                  let identifierPattern = firstBinding.pattern.as(IdentifierPatternSyntax.self),
                  let initializer = firstBinding.initializer?.value else {
                continue
            }
            bindings[identifierPattern.identifier.text] = initializer
        }
        return bindings
    }
}
