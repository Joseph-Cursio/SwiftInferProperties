import SwiftInferCore
import SwiftSyntax

/// TestLifter M7.0 — companion file holding the per-pattern detection
/// functions for the M5 patterns (monotonicity / count-invariance /
/// reduce-equivalence). Split out of the main
/// `AsymmetricAssertionDetector.swift` to keep that file under
/// SwiftLint's 400-line file-length limit. The shared helpers
/// (`inequalityPair`, `calleeName`, `InequalityPair`) live in the
/// main file with internal visibility.
extension AsymmetricAssertionDetector {

    // MARK: - Monotonicity negative — `< precondition; > conclusion`

    static func detectMonotonicityNegative(
        conclusion: AssertionInvocation,
        candidatePreconditions: [CodeBlockItemSyntax]
    ) -> DetectedAsymmetricAssertion? {
        guard let resultPair = parseAntiMonotonicConclusion(conclusion) else {
            return nil
        }
        guard hasMatchingStrictLessThanPrecondition(
            leftArg: resultPair.leftArg,
            rightArg: resultPair.rightArg,
            candidates: candidatePreconditions
        ) else {
            return nil
        }
        return .monotonicity(calleeName: resultPair.calleeName)
    }

    private struct ConclusionShape {
        let calleeName: String
        let leftArg: String
        let rightArg: String
    }

    private static func parseAntiMonotonicConclusion(
        _ assertion: AssertionInvocation
    ) -> ConclusionShape? {
        switch assertion.kind {
        case .xctAssertGreaterThan, .xctAssertGreaterThanOrEqual:
            return parseXCTestConclusionPair(assertion.arguments)
        case .expectMacro:
            return parseSwiftTestingGreaterThanConclusion(assertion.arguments.first)
        default:
            return nil
        }
    }

    private static func parseXCTestConclusionPair(
        _ arguments: [ExprSyntax]
    ) -> ConclusionShape? {
        guard arguments.count == 2,
              let leftCall = arguments[0].as(FunctionCallExprSyntax.self),
              let rightCall = arguments[1].as(FunctionCallExprSyntax.self) else {
            return nil
        }
        return matchedCallShape(leftCall: leftCall, rightCall: rightCall)
    }

    private static func parseSwiftTestingGreaterThanConclusion(
        _ argument: ExprSyntax?
    ) -> ConclusionShape? {
        guard let argument else {
            return nil
        }
        guard let comparison = greaterThanComparison(in: argument),
              let leftCall = comparison.lhs.as(FunctionCallExprSyntax.self),
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
              let leftArg = leftCall.arguments.first?.expression
                .as(DeclReferenceExprSyntax.self),
              let rightArg = rightCall.arguments.first?.expression
                .as(DeclReferenceExprSyntax.self),
              leftArg.baseName.text != rightArg.baseName.text else {
            return nil
        }
        return ConclusionShape(
            calleeName: leftCallee,
            leftArg: leftArg.baseName.text,
            rightArg: rightArg.baseName.text
        )
    }

    private static func hasMatchingStrictLessThanPrecondition(
        leftArg: String,
        rightArg: String,
        candidates: [CodeBlockItemSyntax]
    ) -> Bool {
        for item in candidates {
            guard case .expr(let expr) = item.item else {
                continue
            }
            if matchesXCTestStrictLessThan(expr: expr, leftArg: leftArg, rightArg: rightArg) {
                return true
            }
            if matchesSwiftTestingStrictLessThan(expr: expr, leftArg: leftArg, rightArg: rightArg) {
                return true
            }
        }
        return false
    }

    private static func matchesXCTestStrictLessThan(
        expr: ExprSyntax,
        leftArg: String,
        rightArg: String
    ) -> Bool {
        guard let call = expr.as(FunctionCallExprSyntax.self),
              let ref = call.calledExpression.as(DeclReferenceExprSyntax.self),
              ref.baseName.text == "XCTAssertLessThan",
              call.arguments.count == 2,
              let firstRef = call.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
              let secondRef = call.arguments.dropFirst().first?.expression
                .as(DeclReferenceExprSyntax.self) else {
            return false
        }
        return firstRef.baseName.text == leftArg && secondRef.baseName.text == rightArg
    }

    private static func matchesSwiftTestingStrictLessThan(
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

    // MARK: - Count-invariance negative — `f(xs).count != xs.count`

    static func detectCountInvarianceNegative(
        assertion: AssertionInvocation
    ) -> DetectedAsymmetricAssertion? {
        guard let pair = inequalityPair(in: assertion) else {
            return nil
        }
        if let detected = countInvarianceNegativePair(transform: pair.lhs, input: pair.rhs) {
            return detected
        }
        return countInvarianceNegativePair(transform: pair.rhs, input: pair.lhs)
    }

    private static func countInvarianceNegativePair(
        transform: ExprSyntax,
        input: ExprSyntax
    ) -> DetectedAsymmetricAssertion? {
        guard let transformBase = countMemberBase(of: transform),
              let transformCall = transformBase.as(FunctionCallExprSyntax.self),
              let callee = calleeName(of: transformCall.calledExpression),
              let transformArg = transformCall.arguments.first?.expression,
              let transformArgRef = transformArg.as(DeclReferenceExprSyntax.self),
              let inputBase = countMemberBase(of: input),
              let inputRef = inputBase.as(DeclReferenceExprSyntax.self),
              transformArgRef.baseName.text == inputRef.baseName.text else {
            return nil
        }
        return .countInvariance(calleeName: callee)
    }

    // MARK: - Reduce-equivalence negative —
    // `xs.reduce(s, op) != xs.reversed().reduce(s, op)`

    static func detectReduceEquivalenceNegative(
        assertion: AssertionInvocation
    ) -> DetectedAsymmetricAssertion? {
        guard let pair = inequalityPair(in: assertion) else {
            return nil
        }
        if let detected = reduceEquivalenceNegativePair(lhs: pair.lhs, rhs: pair.rhs) {
            return detected
        }
        return reduceEquivalenceNegativePair(lhs: pair.rhs, rhs: pair.lhs)
    }

    private static func reduceEquivalenceNegativePair(
        lhs: ExprSyntax,
        rhs: ExprSyntax
    ) -> DetectedAsymmetricAssertion? {
        guard let directShape = parseReduce(lhs),
              let reversedShape = parseReduce(rhs),
              !directShape.isReversed,
              reversedShape.isReversed,
              directShape.collectionName == reversedShape.collectionName,
              directShape.seedSource == reversedShape.seedSource,
              directShape.opCalleeName == reversedShape.opCalleeName else {
            return nil
        }
        return .reduceEquivalence(opCalleeName: directShape.opCalleeName)
    }

    private struct ReduceShape {
        let collectionName: String
        let seedSource: String
        let opCalleeName: String
        let isReversed: Bool
    }

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
        if let directRef = base.as(DeclReferenceExprSyntax.self) {
            return ReduceShape(
                collectionName: directRef.baseName.text,
                seedSource: seedExpr.expression.trimmedDescription,
                opCalleeName: opRef.baseName.text,
                isReversed: false
            )
        }
        if let reversedCall = base.as(FunctionCallExprSyntax.self),
           let reversedMember = reversedCall.calledExpression.as(MemberAccessExprSyntax.self),
           reversedMember.declName.baseName.text == "reversed",
           reversedCall.arguments.isEmpty,
           let reversedBaseRef = reversedMember.base?.as(DeclReferenceExprSyntax.self) {
            return ReduceShape(
                collectionName: reversedBaseRef.baseName.text,
                seedSource: seedExpr.expression.trimmedDescription,
                opCalleeName: opRef.baseName.text,
                isReversed: true
            )
        }
        return nil
    }

    // MARK: - Shared comparison + count-member helpers

    private struct OrderingComparison {
        let lhs: ExprSyntax
        let rhs: ExprSyntax
    }

    private static func greaterThanComparison(in expr: ExprSyntax) -> OrderingComparison? {
        if let sequence = expr.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            guard elements.count == 3,
                  let opExpr = elements[1].as(BinaryOperatorExprSyntax.self),
                  opExpr.operator.text == ">" || opExpr.operator.text == ">=" else {
                return nil
            }
            return OrderingComparison(lhs: elements[0], rhs: elements[2])
        }
        if let infix = expr.as(InfixOperatorExprSyntax.self),
           let opExpr = infix.operator.as(BinaryOperatorExprSyntax.self),
           opExpr.operator.text == ">" || opExpr.operator.text == ">=" {
            return OrderingComparison(lhs: infix.leftOperand, rhs: infix.rightOperand)
        }
        return nil
    }

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

    private static func countMemberBase(of expr: ExprSyntax) -> ExprSyntax? {
        guard let member = expr.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "count",
              let base = member.base else {
            return nil
        }
        return base
    }
}
