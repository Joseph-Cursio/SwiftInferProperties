import SwiftInferCore
import SwiftInferTemplates

/// The result laws of the arity-free totality arm, moved out of `InteractiveTriage+AcceptTotality.swift`
/// when the predicate reach test (#665 4b) took that file past SwiftLint's 400-line ceiling.
extension InteractiveTriage {

    /// The laws that check what the call returned — a non-negative measure, a documented range, a
    /// comparator's order — or `nil` for totality, which checks only that it returned. Split out of
    /// `totalityStub`, which builds the call all four share.
    static func resultLawStub(
        _ law: ArityFreeLaw,
        callee: CalleeReference,
        label: String,
        seed: SamplingSeed.Value,
        draws: (generators: [String], argumentTypes: [String])
    ) -> String? {
        let (generators, argumentTypes) = draws
        switch law {
        case .totality:
            return nil

        case .nonNegative:
            return LiftedTestEmitter.nonNegative(
                callee: callee,
                seed: seed,
                generators: generators,
                argumentTypes: argumentTypes,
                failureLabel: "\(label) returned a negative measure"
            )

        case .withinRange(let range):
            return LiftedTestEmitter.withinDocumentedRange(
                callee: callee,
                range: range,
                seed: seed,
                generators: generators,
                failureLabel: "\(label) left its documented range \(range.lower)...\(range.upper)",
                argumentTypes: argumentTypes
            )

        case .sortedBy(let ordering):
            return LiftedTestEmitter.sortedByKey(
                callee: callee,
                ordering: ordering,
                seed: seed,
                generators: generators,
                failureLabel: "\(label) returned a result out of its comparator's order",
                argumentTypes: argumentTypes
            )

        case .independentOfInputOrder(let ordering):
            return LiftedTestEmitter.inputOrderIndependent(
                callee: callee,
                ordering: ordering,
                seed: seed,
                generators: generators,
                failureLabel: "\(label) returned another order for the same input reversed",
                argumentTypes: argumentTypes
            )
        }
    }
}
