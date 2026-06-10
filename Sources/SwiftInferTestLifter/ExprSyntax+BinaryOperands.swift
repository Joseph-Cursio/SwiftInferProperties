import SwiftSyntax

extension ExprSyntax {
    /// The two operands of a binary comparison whose operator text is in
    /// `operators`.
    ///
    /// SwiftParser doesn't fold operator precedence at parse time, so `x OP y`
    /// usually arrives as a three-element `SequenceExprSyntax` (lhs, `OP`, rhs);
    /// the folded `InfixOperatorExprSyntax` shape is also accepted. Returns
    /// `nil` for any other shape or an operator outside `operators`.
    ///
    /// Previously copy-pasted as the `collapsedFromSequence` / `equalityPair`
    /// (`==`), `inequalityFromExpectArg` (`!=`), `greaterThanComparison`
    /// (`>`/`>=`), `strictLessThanComparison` (`<`), and `orderingComparison`
    /// (`<`/`<=`) scaffolds across the assertion detectors.
    func binaryOperands(matching operators: Set<String>) -> (lhs: ExprSyntax, rhs: ExprSyntax)? {
        if let sequence = self.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            guard elements.count == 3,
                  let opExpr = elements[1].as(BinaryOperatorExprSyntax.self),
                  operators.contains(opExpr.operator.text) else {
                return nil
            }
            return (elements[0], elements[2])
        }
        if let infix = self.as(InfixOperatorExprSyntax.self),
           let opExpr = infix.operator.as(BinaryOperatorExprSyntax.self),
           operators.contains(opExpr.operator.text) {
            return (infix.leftOperand, infix.rightOperand)
        }
        return nil
    }

    /// The two operands of an `==` comparison. See `binaryOperands(matching:)`.
    var equalityOperands: (lhs: ExprSyntax, rhs: ExprSyntax)? {
        binaryOperands(matching: ["=="])
    }
}
