import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// The algebraic per-template verifier stubs (commutativity / associativity /
/// identity-element / inverse-pair), split out of `InteractiveTriage+Accept.swift`
/// to keep that file within the length limit. Dispatched by `templateStub(for:)`;
/// no behavior change from the move.
extension InteractiveTriage {

    static func commutativeStub(for suggestion: Suggestion) -> String? {
        guard let evidence = suggestion.evidence.first,
              let callee = CalleeReference(evidence: evidence),
              let typeName = paramType(from: evidence.signature) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.commutative(
            callee: callee,
            typeName: typeName,
            seed: seed,
            generator: chooseGenerator(for: suggestion, typeName: typeName)
        )
    }

    static func associativeStub(for suggestion: Suggestion) -> String? {
        guard let evidence = suggestion.evidence.first,
              let callee = CalleeReference(evidence: evidence),
              let typeName = paramType(from: evidence.signature) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.associative(
            callee: callee,
            typeName: typeName,
            seed: seed,
            generator: chooseGenerator(for: suggestion, typeName: typeName)
        )
    }

    /// IdentityElementTemplate emits 2-row evidence: row 0 binary op,
    /// row 1 identity element (displayName like `"IntSet.empty"` or `"empty"`,
    /// signature `": T"`). Mirror of
    /// `WitnessExtractor.identityWitnessName(from:)` — strips the
    /// optional type prefix so the emitter receives the bare member
    /// name and references it as `\(typeName).\(identityName)`.
    static func identityElementStub(for suggestion: Suggestion) -> String? {
        guard suggestion.evidence.count >= 2,
              let opEvidence = suggestion.evidence.first,
              let identityEvidence = suggestion.evidence.dropFirst().first,
              let callee = CalleeReference(evidence: opEvidence),
              let typeName = paramType(from: opEvidence.signature) else {
            return nil
        }
        let identityName = bareIdentityName(from: identityEvidence.displayName)
        guard !identityName.isEmpty else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.identityElement(
            callee: callee,
            typeName: typeName,
            identityName: identityName,
            seed: seed,
            generator: chooseGenerator(for: suggestion, typeName: typeName)
        )
    }

    static func inversePairStub(for suggestion: Suggestion) -> String? {
        guard suggestion.evidence.count >= 2,
              let forwardEvidence = suggestion.evidence.first,
              let reverseEvidence = suggestion.evidence.dropFirst().first,
              let forward = CalleeReference(evidence: forwardEvidence),
              let inverse = CalleeReference(evidence: reverseEvidence),
              let forwardParam = paramType(from: forwardEvidence.signature) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.inversePair(
            forward: forward,
            inverse: inverse,
            typeName: forwardParam,
            seed: seed,
            generator: chooseGenerator(for: suggestion, typeName: forwardParam),
            equalityKind: equalityKind(forTypeText: forwardParam)
        )
    }
}
