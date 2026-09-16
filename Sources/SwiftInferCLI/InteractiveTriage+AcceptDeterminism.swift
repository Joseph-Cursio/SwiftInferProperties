import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// The determinism arm of the accept path.
///
/// Split out of `InteractiveTriage+Accept.swift`, which crossed SwiftLint's file-length cap when
/// #498 threaded argument types through to the emitter. It sits apart for the same reason
/// `+AcceptTotality` does: determinism is the seed-driven generic law rather than a signature
/// template, and it dispatches ahead of the template switch.
extension InteractiveTriage {

    static func deterministicStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)? = nil
    ) -> String? {
        guard let evidence = suggestion.evidence.first,
              let callee = CalleeReference(evidence: evidence),
              let argumentTypes = arityFreeArgumentTypes(callee: callee, evidence: evidence) else {
            return nil
        }
        // Async / throwing candidates render as `(P0) async throws -> U` (Swift
        // order) in the evidence signature — detect the markers, then strip them
        // so the return-type extraction stays untouched. The emitter reassembles
        // the effect prefix (`await` / `try?`) on the call.
        let isAsync = evidence.signature.contains(" async")
        let isThrows = evidence.signature.contains(" throws")
        let signature = evidence.signature
            .replacingOccurrences(of: " async throws ->", with: " ->")
            .replacingOccurrences(of: " async ->", with: " ->")
            .replacingOccurrences(of: " throws ->", with: " ->")
        guard let returnTypeText = returnType(from: signature) else { return nil }
        let generators = argumentTypes.map { typeName in
            boundedDeterminismGenerator(forTypeName: typeName)
                ?? chooseGenerator(for: suggestion, typeName: typeName, customGenerator: customGenerator)
        }
        return LiftedTestEmitter.deterministic(
            callee: callee,
            generators: generators,
            seed: SamplingSeed.derive(from: suggestion.identity),
            equalityKind: equalityKind(forTypeText: returnTypeText),
            isAsync: isAsync,
            isThrows: isThrows,
            // #498 — the types were already in hand here and the emitter never saw them.
            argumentTypes: argumentTypes
        )
    }
}
