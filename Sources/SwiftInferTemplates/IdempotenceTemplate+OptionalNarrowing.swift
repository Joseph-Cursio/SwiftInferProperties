import Foundation
import SwiftInferCore

// The optional-narrowing type-symmetry signal. A `(T?) -> T` function is still
// idempotence-well-formed: `f(f(x))` typechecks because the non-optional result
// promotes back to `T?`. Common for coalesce / merge-with-default shapes where
// the input may be absent but the output never is — e.g.
// `mergedWith(existing: [String]?) -> [String]`.
extension IdempotenceTemplate {

    static func optionalNarrowingSignal(returnType: String, summary: FunctionSummary) -> Signal? {
        guard summary.parameters.count == 1,
              let param = summary.parameters.first,
              !param.isInout,
              isOptional(param.typeText, of: returnType) else {
            return nil
        }
        return Signal(
            kind: .typeSymmetrySignature,
            weight: 30,
            detail: "Type-symmetry signature: T? -> T (T = \(returnType))"
        )
    }

    /// Whether `candidate` is the `Optional` of `base` — written as `T?` or
    /// `Optional<T>`.
    ///
    /// Delegates to `IdempotenceCandidateShape` rather than keeping a second
    /// copy: the scanner's gate decides whether the return-shape VETO is even
    /// computed, and when these two disagreed the veto silently stopped applying
    /// to every shape only this side admitted.
    private static func isOptional(_ candidate: String, of base: String) -> Bool {
        IdempotenceCandidateShape.isOptional(candidate, of: base)
    }
}
