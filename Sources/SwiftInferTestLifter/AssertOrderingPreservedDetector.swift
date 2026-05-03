import SwiftInferCore
import SwiftSyntax

/// PRD §7.3 "Assert-Ordering-Preserved → monotonicity" detector. Runs
/// against a `SlicedTestBody` looking for the two-statement
/// precondition + conclusion shape that asserts a function preserves
/// ordering of its argument: `a < b ⇒ f(a) <= f(b)` (or `f(a) < f(b)`
/// for strict monotonicity — both produce the same `+20` cross-
/// validation signal per PRD §4.1).
///
/// **Recognized shapes:**
/// - **XCTest two-assert form:**
///   ```
///   XCTAssertLessThan(a, b)
///   XCTAssertLessThanOrEqual(applyDiscount(a), applyDiscount(b))
///   // — or, strict-result variant —
///   XCTAssertLessThan(applyDiscount(a), applyDiscount(b))
///   ```
/// - **Swift Testing two-`#expect` form:**
///   ```
///   #expect(a < b)
///   #expect(applyDiscount(a) <= applyDiscount(b))
///   // strict-result `#expect(applyDiscount(a) < applyDiscount(b))` also detected
///   ```
///
/// Slicer behavior: the conclusion is the LAST recognized assertion in
/// the body (so it lands as `slice.assertion`); the precondition
/// `XCTAssertLessThan(a, b)` / `#expect(a < b)` doesn't bind anything
/// in the live set so it falls through to `slice.setup`. M5.1's slicer
/// extension (`AssertionInvocation.Kind` adds `.xctAssertLessThan` +
/// `.xctAssertLessThanOrEqual`) ensures `XCTAssertLessThan` /
/// `XCTAssertLessThanOrEqual` are recognized as terminal assertions
/// rather than falling through to "no terminal" → empty slice.
///
/// **Single-callee invariant.** The conclusion's `f(a)` and `f(b)`
/// reference the same `f`. `f(a) <= g(b)` is rejected (different
/// callees aren't monotonic; that's a different relationship).
///
/// **Distinct-argument invariant.** The two argument identifiers are
/// textually distinct (`a` vs `b`). `f(a) <= f(a)` (no precondition
/// asymmetry) is a tautology — we'd need `a < a` to also be true,
/// which never is.
///
/// **Argument-order invariant.** The conclusion's argument order
/// matches the precondition's: `a < b` paired with `f(a) <= f(b)`
/// detects; `a < b` paired with `f(b) <= f(a)` does NOT (that's
/// anti-monotonicity, not in scope).
public enum AssertOrderingPreservedDetector {

    public static func detect(in slice: SlicedTestBody) -> [DetectedMonotonicity] {
        guard let conclusion = slice.assertion else {
            return []
        }
        // Walk setup + propertyRegion looking for a precondition `a < b`
        // statement that pairs with the terminal `f(a) <= f(b)`
        // conclusion. Setup is the typical home (the precondition
        // doesn't bind anything in the live set so the slicer routes
        // it there); propertyRegion is checked too in case future
        // slicer changes pull it into the slice.
        let candidates = slice.setup + slice.propertyRegion
        guard let detected = detectFromConclusion(
            conclusion: conclusion,
            candidatePreconditions: candidates
        ) else {
            return []
        }
        return [detected]
    }

    // MARK: - Conclusion + precondition pairing

    private static func detectFromConclusion(
        conclusion: AssertionInvocation,
        candidatePreconditions: [CodeBlockItemSyntax]
    ) -> DetectedMonotonicity? {
        guard let resultPair = parseConclusion(conclusion) else {
            return nil
        }
        guard hasMatchingPrecondition(
            leftArg: resultPair.leftArg,
            rightArg: resultPair.rightArg,
            candidates: candidatePreconditions
        ) else {
            return nil
        }
        return DetectedMonotonicity(
            calleeName: resultPair.calleeName,
            leftArgName: resultPair.leftArg,
            rightArgName: resultPair.rightArg,
            assertionLocation: conclusion.location
        )
    }

    /// One result of parsing the conclusion `f(a) <=/< f(b)` — carries
    /// the same-callee `f` and the two argument identifier names.
    private struct ConclusionShape {
        let calleeName: String
        let leftArg: String
        let rightArg: String
    }

    /// Parse the conclusion. For XCTest, the assertion's two arguments
    /// are `f(leftArg)` and `f(rightArg)`. For Swift Testing, the
    /// assertion's single argument is an infix `f(leftArg) <= f(rightArg)`
    /// (or `<`).
    private static func parseConclusion(_ assertion: AssertionInvocation) -> ConclusionShape? {
        switch assertion.kind {
        case .xctAssertLessThan, .xctAssertLessThanOrEqual:
            return parseXCTestConclusion(assertion.arguments)
        case .expectMacro:
            return parseSwiftTestingConclusion(assertion.arguments.first)
        case .xctAssertEqual, .xctAssertTrue, .xctAssert, .xctAssertNotNil,
                .xctAssertNotEqual, .xctAssertGreaterThan,
                .xctAssertGreaterThanOrEqual, .requireMacro:
            return nil
        }
    }

    private static func parseXCTestConclusion(_ arguments: [ExprSyntax]) -> ConclusionShape? {
        guard arguments.count == 2,
              let leftCall = arguments[0].as(FunctionCallExprSyntax.self),
              let rightCall = arguments[1].as(FunctionCallExprSyntax.self) else {
            return nil
        }
        return matchedCallShape(leftCall: leftCall, rightCall: rightCall)
    }

    private static func parseSwiftTestingConclusion(_ argument: ExprSyntax?) -> ConclusionShape? {
        guard let argument else {
            return nil
        }
        guard let comparison = orderingComparison(in: argument) else {
            return nil
        }
        guard let leftCall = comparison.lhs.as(FunctionCallExprSyntax.self),
              let rightCall = comparison.rhs.as(FunctionCallExprSyntax.self) else {
            return nil
        }
        return matchedCallShape(leftCall: leftCall, rightCall: rightCall)
    }

    private static func matchedCallShape(
        leftCall: FunctionCallExprSyntax,
        rightCall: FunctionCallExprSyntax
    ) -> ConclusionShape? {
        guard let leftCallee = calleeName(of: leftCall.calledExpression),
              let rightCallee = calleeName(of: rightCall.calledExpression),
              leftCallee == rightCallee,
              let leftArgExpr = leftCall.arguments.first?.expression,
              let rightArgExpr = rightCall.arguments.first?.expression,
              let leftArg = leftArgExpr.as(DeclReferenceExprSyntax.self),
              let rightArg = rightArgExpr.as(DeclReferenceExprSyntax.self),
              leftArg.baseName.text != rightArg.baseName.text else {
            return nil
        }
        return ConclusionShape(
            calleeName: leftCallee,
            leftArg: leftArg.baseName.text,
            rightArg: rightArg.baseName.text
        )
    }

    /// `lhs` and `rhs` of the parsed `<` / `<=` comparison.
    private struct OrderingComparison {
        let lhs: ExprSyntax
        let rhs: ExprSyntax
    }

    /// Pull the `<` / `<=` comparison out of a `#expect(...)` argument,
    /// supporting both `SequenceExprSyntax` (pre-fold parser shape) and
    /// `InfixOperatorExprSyntax` (folded shape).
    private static func orderingComparison(in expr: ExprSyntax) -> OrderingComparison? {
        if let sequence = expr.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            guard elements.count == 3,
                  let opExpr = elements[1].as(BinaryOperatorExprSyntax.self),
                  isOrderingOperator(opExpr.operator.text) else {
                return nil
            }
            return OrderingComparison(lhs: elements[0], rhs: elements[2])
        }
        if let infix = expr.as(InfixOperatorExprSyntax.self),
           let opExpr = infix.operator.as(BinaryOperatorExprSyntax.self),
           isOrderingOperator(opExpr.operator.text) {
            return OrderingComparison(lhs: infix.leftOperand, rhs: infix.rightOperand)
        }
        return nil
    }

    private static func isOrderingOperator(_ token: String) -> Bool {
        token == "<" || token == "<="
    }

    // MARK: - Precondition matching

    /// Walk `candidates` looking for a statement that asserts
    /// `leftArg < rightArg` — either `XCTAssertLessThan(leftArg,
    /// rightArg)` or `#expect(leftArg < rightArg)`. Strict `<` only;
    /// `<=` precondition would weaken the monotonicity claim into a
    /// reflexive-friendly variant we don't recognise in M5.1.
    private static func hasMatchingPrecondition(
        leftArg: String,
        rightArg: String,
        candidates: [CodeBlockItemSyntax]
    ) -> Bool {
        for item in candidates {
            guard case .expr(let expr) = item.item else {
                continue
            }
            if matchesXCTestPrecondition(expr: expr, leftArg: leftArg, rightArg: rightArg) {
                return true
            }
            if matchesSwiftTestingPrecondition(expr: expr, leftArg: leftArg, rightArg: rightArg) {
                return true
            }
        }
        return false
    }

    private static func matchesXCTestPrecondition(
        expr: ExprSyntax,
        leftArg: String,
        rightArg: String
    ) -> Bool {
        guard let call = expr.as(FunctionCallExprSyntax.self),
              let ref = call.calledExpression.as(DeclReferenceExprSyntax.self),
              ref.baseName.text == "XCTAssertLessThan",
              call.arguments.count == 2,
              let firstRef = call.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
              let secondRef = call.arguments.dropFirst().first?.expression.as(DeclReferenceExprSyntax.self) else {
            return false
        }
        return firstRef.baseName.text == leftArg && secondRef.baseName.text == rightArg
    }

    private static func matchesSwiftTestingPrecondition(
        expr: ExprSyntax,
        leftArg: String,
        rightArg: String
    ) -> Bool {
        guard let macro = expr.as(MacroExpansionExprSyntax.self),
              macro.macroName.text == "expect",
              let firstArg = macro.arguments.first?.expression else {
            return false
        }
        guard let comparison = strictLessThanComparison(in: firstArg),
              let lhsRef = comparison.lhs.as(DeclReferenceExprSyntax.self),
              let rhsRef = comparison.rhs.as(DeclReferenceExprSyntax.self) else {
            return false
        }
        return lhsRef.baseName.text == leftArg && rhsRef.baseName.text == rightArg
    }

    /// Pull `lhs < rhs` out of a `#expect(...)` argument — strict only.
    /// Not extracted from `orderingComparison(in:)` because the
    /// precondition needs strict `<` while the conclusion accepts both
    /// `<` and `<=`.
    private static func strictLessThanComparison(in expr: ExprSyntax) -> OrderingComparison? {
        if let sequence = expr.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            guard elements.count == 3,
                  let opExpr = elements[1].as(BinaryOperatorExprSyntax.self),
                  opExpr.operator.text == "<" else {
                return nil
            }
            return OrderingComparison(lhs: elements[0], rhs: elements[2])
        }
        if let infix = expr.as(InfixOperatorExprSyntax.self),
           let opExpr = infix.operator.as(BinaryOperatorExprSyntax.self),
           opExpr.operator.text == "<" {
            return OrderingComparison(lhs: infix.leftOperand, rhs: infix.rightOperand)
        }
        return nil
    }

    // MARK: - Helpers

    private static func calleeName(of expr: ExprSyntax) -> String? {
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }
}
