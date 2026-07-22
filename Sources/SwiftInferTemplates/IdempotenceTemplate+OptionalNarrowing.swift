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
    private static func isOptional(_ candidate: String, of base: String) -> Bool {
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespaces)
        let trimmedBase = base.trimmingCharacters(in: .whitespaces)
        return trimmedCandidate == "\(trimmedBase)?"
            || trimmedCandidate == "Optional<\(trimmedBase)>"
    }
}
