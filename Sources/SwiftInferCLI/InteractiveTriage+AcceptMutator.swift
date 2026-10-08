import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// The mutator arm of the accept path — the stubs for `mutator-determinism` and
/// `mutator-idempotence` (`Discover+MutatorLaws`).
///
/// `SubjectCallPlan` declines both shapes a mutator has, and rightly for the laws it plans: a
/// `mutating` method cannot be called on a drawn receiver, which is immutable, and an `inout`
/// parameter cannot take a drawn `let`. A mutator's laws never call it on the drawn value — they
/// copy it into a `var` first — so they are written here instead, as the totality arm writes an
/// `inout` subject.
extension InteractiveTriage {

    /// The stub for a synthesized mutator law, or `nil` when the suggestion is not one or its call
    /// cannot be spelled.
    static func mutatorStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)? = nil
    ) -> String? {
        let law: LiftedTestEmitter.MutatorLaw
        switch suggestion.templateName {
        case "mutator-determinism": law = .determinism
        case "mutator-idempotence": law = .idempotence
        default: return nil
        }
        guard let evidence = suggestion.evidence.first, let call = mutatorCall(for: evidence) else { return nil }
        let generators = call.argumentTypes.map { typeName in
            boundedDeterminismGenerator(forTypeName: typeName)
                ?? chooseGenerator(for: suggestion, typeName: typeName, customGenerator: customGenerator)
        }
        let subject = LiftedTestEmitter.MutatorSubject(
            callee: call.callee,
            generators: generators,
            mutatedIndex: call.mutatedIndex,
            mutatesReceiver: evidence.isMutatingMethod,
            isThrows: determinismEffects(in: evidence.signature).isThrows,
            argumentTypes: call.argumentTypes
        )
        return LiftedTestEmitter.mutatorLaw(law, subject: subject, seed: SamplingSeed.derive(from: suggestion.identity))
    }

    /// How a mutator law calls its subject: the callee, one type per drawn argument (the receiver
    /// first for an instance method), and which of them the mutator writes.
    struct MutatorCall: Equatable {
        let callee: CalleeReference
        let argumentTypes: [String]
        let mutatedIndex: Int
    }

    /// The call for `evidence`, or `nil` when it is not a mutator a stub can spell: a `mutating`
    /// method with no `inout` parameter (it writes its receiver, drawn first), or a non-mutating
    /// function with exactly one (it writes that argument). `async` is refused, as the producer
    /// refuses it.
    static func mutatorCall(for evidence: Evidence) -> MutatorCall? {
        guard !determinismEffects(in: evidence.signature).isAsync else { return nil }
        if evidence.isMutatingMethod {
            guard evidence.inoutParameterIndices.isEmpty,
                  let callee = CalleeReference.mutatingStatement(evidence: evidence),
                  let types = arityFreeArgumentTypes(callee: callee, evidence: evidence) else {
                return nil
            }
            return MutatorCall(callee: callee, argumentTypes: types, mutatedIndex: 0)
        }
        guard evidence.inoutParameterIndices.count == 1,
              let index = evidence.inoutParameterIndices.first,
              let callee = CalleeReference(evidence: evidence),
              let types = arityFreeArgumentTypes(callee: callee, evidence: evidence) else {
            return nil
        }
        return MutatorCall(
            callee: callee,
            argumentTypes: types,
            mutatedIndex: index + (callee.isInstanceMethod ? 1 : 0)
        )
    }
}
