import SwiftInferCore
import SwiftInferTemplates

extension InteractiveTriage {

    /// An empty range selects nothing — `EmptyRangeTemplate`. The template admits only a free or
    /// static `(from: T, to: T)`, so the callee needs no receiver and one drawn `T` serves as both
    /// ends.
    static func emptyRangeStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)?
    ) -> String? {
        guard let evidence = suggestion.evidence.first,
              let callee = CalleeReference(evidence: evidence),
              !callee.isInstanceMethod,
              let types = arityFreeArgumentTypes(callee: callee, evidence: evidence),
              types.count == 2, types[0] == types[1] else {
            return nil
        }
        let generator = chooseGenerator(for: suggestion, typeName: types[0], customGenerator: customGenerator)
        return LiftedTestEmitter.emptyRange(
            callee: callee,
            bound: (typeName: types[0], generator: generator),
            seed: SamplingSeed.derive(from: suggestion.identity)
        )
    }
}
