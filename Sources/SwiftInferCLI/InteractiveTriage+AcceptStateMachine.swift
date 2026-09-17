import SwiftInferCore
import SwiftInferTemplates

/// `state-machine`'s accept arm: a SCAFFOLD naming the two moves (#478).
///
/// Split out of `InteractiveTriage+AcceptTotality.swift`, whose switch dispatches here, because a
/// scaffold shares nothing with the runnable entailed writers beside it — no generator, no trial
/// loop, no equality kind.
extension InteractiveTriage {

    /// The scaffold for a `state-machine` suggestion, or `nil` for a row that does not name a pair
    /// on a carrier.
    ///
    /// **Spelled from the evidence, not from `CalleeReference`.** That type answers `nil` for a
    /// mutating method, on the grounds that such a method returns nothing for a law to compare —
    /// and a state-machine move is exactly a `Void`, usually mutating, method. Its law compares the
    /// STATE the moves leave behind, not a return value, so the declines `CalleeReference` exists to
    /// give do not apply here.
    ///
    /// The template orders its evidence `[forward, backward]` and states `backward ∘ forward == id`,
    /// so the scaffold applies them in that order.
    static func stateMachineScaffold(for suggestion: Suggestion) -> String? {
        guard suggestion.evidence.count >= 2,
              let carrier = suggestion.carrier,
              let forward = stateMachineMove(from: suggestion.evidence[0]),
              let backward = stateMachineMove(from: suggestion.evidence[1]) else {
            return nil
        }
        return LiftedTestEmitter.stateMachineScaffold(
            carrier: suggestion.evidence[0].qualifiedTypeName ?? carrier,
            forward: forward,
            backward: backward
        )
    }

    /// A move's name, labels and parameter types, or `nil` when its display name and signature
    /// disagree on how many parameters it takes — a malformed row writes nothing rather than a
    /// call with the wrong arguments.
    static func stateMachineMove(from evidence: Evidence) -> StateMachineMove? {
        guard let name = functionName(from: evidence.displayName) else { return nil }
        let labels = parameterLabels(from: evidence.displayName)
        let types = labels.isEmpty ? [] : parameterTypes(from: evidence.signature)
        guard labels.count == types.count else { return nil }
        return StateMachineMove(
            name: name,
            parameterLabels: labels,
            parameterTypes: types,
            isInstanceMethod: evidence.isInstanceMethod,
            isAsync: evidence.signature.contains(" async"),
            isThrows: evidence.signature.contains(" throws")
        )
    }
}
