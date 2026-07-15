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
              let funcName = functionName(from: evidence.displayName),
              let typeName = paramType(from: evidence.signature) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.commutative(
            funcName: funcName,
            typeName: typeName,
            seed: seed,
            generator: chooseGenerator(for: suggestion, typeName: typeName)
        )
    }

    static func associativeStub(for suggestion: Suggestion) -> String? {
        guard let evidence = suggestion.evidence.first,
              let funcName = functionName(from: evidence.displayName),
              let typeName = paramType(from: evidence.signature) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.associative(
            funcName: funcName,
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
              let funcName = functionName(from: opEvidence.displayName),
              let typeName = paramType(from: opEvidence.signature) else {
            return nil
        }
        let identityName = bareIdentityName(from: identityEvidence.displayName)
        guard !identityName.isEmpty else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.identityElement(
            funcName: funcName,
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
              let forwardName = functionName(from: forwardEvidence.displayName),
              let inverseName = functionName(from: reverseEvidence.displayName),
              let forwardParam = paramType(from: forwardEvidence.signature) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.inversePair(
            forwardName: forwardName,
            inverseName: inverseName,
            typeName: forwardParam,
            seed: seed,
            generator: chooseGenerator(for: suggestion, typeName: forwardParam),
            equalityKind: equalityKind(forTypeText: forwardParam)
        )
    }
}
