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

    /// A keyword table dispatches each marker to its row's case — `MarkerDispatchTemplate`. The
    /// template admits only a chain callable without a receiver, so the callee is the evidence row
    /// as written; a front's lookup is spelled on the same qualifier, with the same isolation.
    static func markerDispatchStub(for suggestion: Suggestion) -> String? {
        guard let match = suggestion.match?.markerDispatchMatch,
              let evidence = suggestion.evidence.first,
              let callee = CalleeReference(evidence: evidence),
              !callee.isInstanceMethod,
              callee.isolation != CalleeReference.actorReceiverIsolation else {
            return nil
        }
        let front = match.front.map {
            CalleeReference(
                bareName: $0.primaryName,
                qualifier: callee.qualifier,
                argumentLabels: [$0.primaryLabel],
                isolation: callee.isolation
            )
        }
        return LiftedTestEmitter.markerDispatch(callee: callee, match: match, front: front)
    }
}
