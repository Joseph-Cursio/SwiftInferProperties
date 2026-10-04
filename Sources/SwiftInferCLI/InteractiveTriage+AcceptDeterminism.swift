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
              determinismResultDeclineReason(for: evidence) == nil,
              let callee = CalleeReference(evidence: evidence),
              let argumentTypes = arityFreeArgumentTypes(callee: callee, evidence: evidence) else {
            return nil
        }
        // Async / throwing candidates render as `(P0) async throws -> U` (Swift
        // order) in the evidence signature — detect the markers, then strip them
        // so the return-type extraction stays untouched. The emitter reassembles
        // the effect prefix (`await` / `try?`) on the call.
        let (isAsync, isThrows) = determinismEffects(in: evidence.signature)
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

    /// The effects the determinism emitter writes around each call: `await` for `async`, and
    /// `try?` for `throws`. One reading, shared by the writer and by its decline, so the decline
    /// fires exactly when the writer would have spelled `try?`.
    ///
    /// **The function's OWN effects** (`FunctionTypeEffects`), not a substring: `" throws"` also
    /// matches a closure parameter's type, and the decline then told the reader a non-throwing
    /// `applyPair(_:_:)` "throws and returns a tuple" while the law's caveats, read from the
    /// scanner's `isThrows`, said it did not. A signature built by `inferenceSignature` spells
    /// exactly the scanner's two flags before its own `->`, so the two now agree. A spelling that
    /// does not parse keeps the substring reading it always had.
    static func determinismEffects(in signature: String) -> (isAsync: Bool, isThrows: Bool) {
        guard let effects = FunctionTypeEffects(signature: signature) else {
            return (signature.contains(" async"), signature.contains(" throws"))
        }
        return (effects.isAsync, effects.isThrows)
    }

    /// Why the determinism law's `==` cannot be written over this subject's result, or `nil` when
    /// it can — keyed on the RESULT type, where every other decline reads the subject's inputs.
    ///
    /// **A tuple never conforms to `Equatable`; Swift defines `==` on tuples of two to six
    /// `Equatable` elements instead** (`TupleResultShape`). So `f(x) == f(x)` over a tuple
    /// compiles, and two shapes of the law do not:
    ///
    /// - **A throwing subject's**, `(try? f(x)) == (try? f(x))`. It compares two `Optional`s of
    ///   the tuple, and `Optional`'s `==` needs its payload to conform — measured with `swiftc` on
    ///   Swift 6.4: *binary operator '==' cannot be applied to two '(text: String, didTruncate:
    ///   Bool)?' operands*. `async throws` is the same case behind an `await`.
    /// - **Any result the spelling alone rules out**: more than six elements, a tuple element, or a
    ///   tuple inside an `Optional` or a collection. SwiftProjectLint is to seed none of these,
    ///   but a hand-written manifest can name any function, so they are refused here too.
    ///
    /// ⚠ **"The spelling" is the limit.** A `typealias` for a tuple reads as its name
    /// (`TupleResultShape`), so a throwing `-> Pair` still gets the `try?` stub, which does not
    /// compile — as a non-`Equatable` nominal result's stub does not. Both need the scan at accept.
    ///
    /// **The law is still synthesized** (`qualifiesForDeterminism` does not look at the result):
    /// it is tautological, so declining its stub costs no refutable law, while dropping it would
    /// also drop the docstring advice's reference-oracle scaffold, which takes its seed from it.
    ///
    /// Read by `StubApplicationArity.declineReason`, so `accept` names this cause rather than
    /// "no stub writeout available" (#456), and by `deterministicStub`, which declines exactly
    /// these — `DeterminismAcceptPathTests` pins both sides.
    static func determinismResultDeclineReason(for evidence: Evidence) -> String? {
        let shape = TupleResultShape(signature: evidence.signature)
        if let obstacle = shape.equalityObstacle {
            return "\(evidence.displayName) returns \(obstacle)"
        }
        guard shape.involvesTuple, determinismEffects(in: evidence.signature).isThrows else { return nil }
        let name = evidence.displayName.prefix { $0 != "(" }
        return "\(evidence.displayName) throws and returns a tuple, so the determinism law would compare "
            + "`try? \(name)(…)` on both sides — and an Optional of a tuple has no `==`, because a tuple "
            + "cannot conform to Equatable"
    }
}
