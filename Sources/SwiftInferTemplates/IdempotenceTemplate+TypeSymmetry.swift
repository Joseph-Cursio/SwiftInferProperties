import SwiftInferCore

/// The four shapes `IdempotenceTemplate` accepts as `T -> T`, in the order it
/// tries them. Split out of `IdempotenceTemplate.swift` when the erased
/// self-form arm pushed that file past the 400-line cap.
///
/// The order is load-bearing: the erased form is tried LAST so it can never
/// shadow a concrete match and quietly downgrade a 30-weight signal to 25.
extension IdempotenceTemplate {

    static func typeSymmetrySignal(
        for summary: FunctionSummary,
        inheritedTypesByName: [String: Set<String>] = [:]
    ) -> Signal? {
        guard !summary.isMutating,
              let returnType = summary.returnTypeText,
              returnType != "Void",
              returnType != "()" else {
            return nil
        }
        // Free / static: exactly one non-`inout` parameter whose type is the
        // return type — `func normalize(_ x: T) -> T`.
        if summary.parameters.count == 1,
           let param = summary.parameters.first,
           !param.isInout,
           returnType == param.typeText {
            return Signal(
                kind: .typeSymmetrySignature,
                weight: 30,
                detail: "Type-symmetry signature: T -> T (T = \(returnType))"
            )
        }
        // Optional-narrowing free / static form — `func mergedWith(_ x: T?) -> T`.
        // (See IdempotenceTemplate+OptionalNarrowing.swift.)
        if let optionalSignal = optionalNarrowingSignal(returnType: returnType, summary: summary) {
            return optionalSignal
        }
        // Instance: zero parameters, returning the containing type —
        // `func normalized() -> Doc` (`self -> Self`). B32 — mirrors
        // InvolutionTemplate's two-shape acceptance so instance idempotent
        // transforms surface, not only the free `f(x)` form. `self` is the
        // operand; `Array`-materialised wrapper returns remain out of scope.
        //
        // The return may be written as the literal `Self` (`var canonicalizedTransform:
        // Self`, `func normalized() -> Self`) — canonicalize it to the container, the
        // same way DualStylePairing / SetAlgebraShape / the binary-op type-symmetry
        // signal already do. Return-position only, and only on the NULLARY self-form,
        // so the binary `merge(_ other: Self)` x-curried-idempotence hazard is untouched.
        if summary.parameters.isEmpty,
           let container = summary.containingTypeName,
           container == returnType || returnType == "Self" {
            let resolved = returnType == "Self" ? container : returnType
            return Signal(
                kind: .typeSymmetrySignature,
                weight: 30,
                detail: "Type-symmetry signature: self -> Self (Self = \(resolved))"
            )
        }
        // Erased self-form — LAST, so it never shadows a concrete match.
        // `extension SyntaxProtocol { func formatted(using:) -> Syntax }`.
        // See IdempotenceTemplate+ErasedSelfForm.swift.
        return erasedSelfFormSignal(
            for: summary,
            inheritedTypesByName: inheritedTypesByName
        )
    }
}
