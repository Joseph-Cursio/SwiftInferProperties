import Foundation
import PropertyLawCore
import SwiftInferCore
import SwiftInferTemplates

/// The accept-path arm for `comparator`: a `(T, T) -> Bool` owes a strict weak ordering (#475).
///
/// Split into its own file because its generator choice is its own: it runs the kit's suite twice,
/// once over the derived draw and once over a tie-dense one, since the clause comparators break
/// most — transitivity of incomparability — only applies to values that tie. See
/// `LiftedTestEmitter.strictWeakOrdering(callee:passes:)` for the measurement behind the second pass.
extension InteractiveTriage {

    /// A strict-weak-ordering stub for a **static or free** comparator, or `nil`.
    ///
    /// Every reachable comparator in the corpus funnel census is `static func precedes…(_ lhs: T,
    /// _ rhs: T) -> Bool` (4 of 4), so the call is a qualified static call inside one kit call.
    /// What declines is named in `comparatorDeclineReason`.
    static func comparatorStub(for suggestion: Suggestion, customGenerator: ((String) -> String?)?) -> String? {
        guard let evidence = suggestion.evidence.first,
              let callee = CalleeReference(evidence: evidence),
              comparatorDeclineReason(callee: callee, evidence: evidence) == nil,
              let operand = parameterTypes(from: evidence.signature).first else {
            return nil
        }
        let wide = chooseGenerator(for: suggestion, typeName: operand, customGenerator: customGenerator)
        // Not the template's `tiedKeys` recipe: for a `String` operand the rewrite already draws from
        // the same alphabet, and the recipe's leading comment block would land in argument position.
        let dense = LiftedTestEmitter.tieDense(wide)
        var passes = [(note: "The derived draw, over the operand type's full range.", generator: wide)]
        if dense != wide {
            passes.append((
                note: "A tie-dense draw. Transitivity of incomparability only applies to values that tie,\n"
                    + "and a wide draw almost never produces one.",
                generator: dense
            ))
        }
        return LiftedTestEmitter.strictWeakOrdering(callee: callee, passes: passes)
    }

    /// Why a comparator cannot be written as a kit call, or `nil` when it can.
    ///
    /// - **An instance method.** The template admits any two unlabelled operands of one type, so
    ///   `func precedes(_:_:)` on a `Sorter` qualifies — but the kit's closure takes two values and
    ///   has nowhere to draw a receiver, and the law is only meaningful with one receiver held fixed
    ///   across a triple. None occurs in the census; declining beats guessing a receiver.
    /// - **An isolated comparator.** The kit calls it from a nonisolated `@Sendable` closure, which
    ///   cannot call an actor-isolated function synchronously (#482 is the target-default case).
    static func comparatorDeclineReason(callee: CalleeReference, evidence: Evidence) -> String? {
        if callee.isInstanceMethod {
            return "\(callee.displaySignature) is an instance method, and the strict-weak-ordering suite's "
                + "comparator closure has no receiver to hold fixed across a triple — only a static or "
                + "free comparator is written"
        }
        if let isolation = callee.isolation {
            return "\(callee.displaySignature) is \(isolation)-isolated, and the suite calls the comparator "
                + "from a nonisolated @Sendable closure"
        }
        if callee.argumentLabels.count != 2 || parameterTypes(from: evidence.signature).count != 2 {
            return "\(callee.displaySignature) does not record two operands, so the comparator cannot be spelled"
        }
        return nil
    }
}
