import SwiftSyntax

extension ExprSyntax {
    /// The two operands of an `==` comparison.
    ///
    /// SwiftParser doesn't fold operator precedence at parse time, so `x == y`
    /// usually arrives as a three-element `SequenceExprSyntax` (lhs, `==`, rhs);
    /// the folded `InfixOperatorExprSyntax` shape is also accepted. Returns
    /// `nil` for any other shape or a non-`==` operator.
    ///
    /// Previously copy-pasted as `collapsedFromSequence` / `equalityPair(in:)`
    /// across five assertion detectors.
    var equalityOperands: (lhs: ExprSyntax, rhs: ExprSyntax)? {
        if let sequence = self.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            guard elements.count == 3,
                  let opExpr = elements[1].as(BinaryOperatorExprSyntax.self),
                  opExpr.operator.text == "==" else {
                return nil
            }
            return (elements[0], elements[2])
        }
        if let infix = self.as(InfixOperatorExprSyntax.self),
           let opExpr = infix.operator.as(BinaryOperatorExprSyntax.self),
           opExpr.operator.text == "==" {
            return (infix.leftOperand, infix.rightOperand)
        }
        return nil
    }
}
