import SwiftInferCore

extension FunctionSummary {
    /// Veto signal raised when the body calls a non-deterministic API: such a
    /// function cannot satisfy a deterministic algebraic property, so the
    /// suggestion is suppressed. `nil` when the body is clean.
    ///
    /// Previously copy-pasted as `nonDeterministicVeto(for summary:)` across
    /// five templates (and delegated to by the IdentityElement and Composition
    /// single-member forms).
    var nonDeterministicVetoSignal: Signal? {
        guard bodySignals.hasNonDeterministicCall else {
            return nil
        }
        let calls = bodySignals.nonDeterministicAPIsDetected.joined(separator: ", ")
        return Signal(
            kind: .nonDeterministicBody,
            weight: Signal.vetoWeight,
            detail: "Non-deterministic API in body: \(calls)"
        )
    }

    /// `+30` signal when the function has the binary-operator type shape
    /// `(T, T) -> T` — two same-typed, non-`inout` parameters returning that
    /// same non-`Void` type, on a non-`mutating` function. `nil` otherwise.
    ///
    /// Shared by the associativity and commutativity templates (which both
    /// gate on `(T, T) -> T`); previously copy-pasted as `typeShapeSignal`.
    var binaryOperatorTypeSymmetrySignal: Signal? {
        guard parameters.count == 2,
              !isMutating else {
            return nil
        }
        let first = parameters[0]
        let second = parameters[1]
        guard !first.isInout,
              !second.isInout,
              first.typeText == second.typeText,
              let returnType = returnTypeText,
              returnType == first.typeText,
              returnType != "Void",
              returnType != "()" else {
            return nil
        }
        return Signal(
            kind: .typeSymmetrySignature,
            weight: 30,
            detail: "Type-symmetry signature: (T, T) -> T (T = \(returnType))"
        )
    }
}
