import SwiftInferCore

extension LiftedTestEmitter {

    /// The property closure's parameter: `pair`, or `(pair: (BigInt, BigInt))` when the subject is
    /// an operator.
    ///
    /// **An untyped closure over an overloaded operator does not type-check in time.** BigInt's
    /// `+` associativity stub, `{ triple in ((triple.0 + triple.1) + triple.2) == … }`, was set
    /// aside on *unable to type-check this expression in reasonable time*: the solver weighs every
    /// `+` in scope against a tuple it knows nothing about. A named function has one candidate, so
    /// only an operator gets the annotation and every other stub keeps its text.
    static func operandBinding(_ name: String, arity: Int, callee: CalleeReference, typeName: String) -> String {
        guard callee.isOperator, !typeName.isEmpty else { return name }
        let tuple = Array(repeating: typeName, count: arity).joined(separator: ", ")
        return "(\(name): (\(tuple)))"
    }
}
