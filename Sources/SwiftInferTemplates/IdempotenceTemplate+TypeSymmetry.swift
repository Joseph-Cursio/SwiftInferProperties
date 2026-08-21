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
        // **`static` is excluded, and the omission cost 49 laws.** The paragraph above
        // says *Instance* and says `self` is the operand — and until 2026-08-21 nothing
        // checked it, so `public static var badGateway: Self` matched: zero parameters,
        // container `Status`, return `Self`. A static member has no receiver, so there is
        // no `self` to apply twice, and the emitter rendered
        // `let applyOnce: (Status) -> Status = Status.badGateway` — a constant where a
        // function belongs. Measured on `swift-http-types` @ `5b99e00`: 49 of 163 laws
        // failed to build on exactly this, `cannot convert value of type
        // 'HTTPResponse.Status' to specified type '(HTTPResponse.Status) -> …'`.
        //
        // `IdempotenceTemplate+ErasedSelfForm.swift` carries `!summary.isStatic` one file
        // away. **A doc asserting a guard is not a guard** — the same finding
        // `SpeculativeWidening`'s enclosing-type trap recorded, in a different file.
        if summary.parameters.isEmpty,
           !summary.isStatic,
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
