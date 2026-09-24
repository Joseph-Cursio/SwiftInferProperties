import Foundation
import SwiftInferCore

/// A law over an instance method whose receiver is a separate object, stated with that receiver
/// held fixed: `codec.decode(codec.encode(x)) == x`.
///
/// ## What this answers
///
/// A template's arity counts the arguments its law applies, and for an instance method the
/// receiver is one of them (`StubApplicationArity`). So `JSONCodec.encode(_:)` needs two
/// arguments and `round-trip` applies one, and the accept path declined it: **103 suggestions
/// across the 19-repository corpus** (census 2026-09-23), `idempotence` 53, `monotonicity` 28,
/// `round-trip` 10, the rest ≤ 4 each. The law was never about the receiver. A codec, a
/// formatter, a normaliser is *configuration*; the law quantifies over the value it is applied
/// to.
///
/// ## How
///
/// The suggestion's evidence is rewritten so the receiver is an expression rather than an
/// argument — the same move `constructedReceiver` makes for totality, applied before any writer
/// runs. Every writer then renders `expression.encode(value)` through `CalleeReference`
/// unchanged, and `StubApplicationArity.declineReason` agrees with it, because the callee now
/// takes exactly the arguments the law applies.
///
/// The receiver is spelled, in order of preference, as the construction the package's own
/// tests write (`receiverExpression`), or as one draw of its derived generator on a fixed seed.
/// Either sits inside the property closure, so no receiver value crosses a `Sendable` boundary.
///
/// ## What it deliberately does not do
///
/// - **A receiver of the parameter's own type is an operand, not configuration.** `a.union(b)`
///   held at `a` makes idempotence the absorbing-versus-accumulating question the hand-check
///   tally already names as a false-law mechanism (`appending` applied twice appends twice). So
///   a row whose receiver type appears among its parameter types is left alone.
/// - **One receiver per stub, not one per trial.** A pass is a statement about that receiver.
///   The trials range over the values the law is about; drawing the configuration too would
///   change every writer's quantifier, and is left for when a held receiver has refuted
///   something worth widening.
enum HeldReceiver {

    /// The suggestion the writers should see: held when its receiver is configuration rather
    /// than an operand, as discovered otherwise.
    static func writable(
        _ suggestion: Suggestion,
        receiverExpression: ((String) -> String?)?,
        customGenerator: ((String) -> String?)?
    ) -> Suggestion {
        let spell = spelling(for: suggestion, receiverExpression: receiverExpression, customGenerator: customGenerator)
        return rewrite(suggestion, spelling: spell) ?? suggestion
    }

    /// `suggestion` with each evidence row's receiver held fixed, or `nil` when the subject
    /// already fits its template or cannot be held.
    ///
    /// Every row must qualify, and all rows must share one receiver type: `round-trip` pairs
    /// `encode` with `decode`, and holding one while drawing the other states nothing.
    static func rewrite(
        _ suggestion: Suggestion,
        spelling: (String) -> String?
    ) -> Suggestion? {
        guard let arity = StubApplicationArity.forTemplate(suggestion.templateName),
              let receiverType = suggestion.evidence.first?.qualifiedTypeName,
              suggestion.evidence.allSatisfy({ isHoldable($0, receiverType: receiverType, arity: arity) }),
              let expression = spelling(receiverType)
        else { return nil }
        var copy = suggestion
        copy.evidence = suggestion.evidence.map { $0.holdingReceiver(as: expression) }
        return copy
    }

    /// Whether `evidence` is an instance method on `receiverType` that takes exactly the
    /// arguments the law applies, none of them of the receiver's own type.
    static func isHoldable(_ evidence: Evidence, receiverType: String, arity: Int) -> Bool {
        guard evidence.qualifiedTypeName == receiverType,
              let callee = CalleeReference(evidence: evidence),
              callee.isInstanceMethod, !callee.isComputedProperty,
              callee.applicationArity == arity + 1
        else { return false }
        let bareReceiver = receiverType.split(separator: ".").last.map(String.init) ?? receiverType
        let parameters = InteractiveTriage.parameterTypes(from: evidence.signature)
        return !parameters.contains { $0 == receiverType || $0 == bareReceiver || $0 == "Self" }
    }

    /// The receiver as an expression: the tests' own construction when there is one, else one
    /// draw of the derived generator on a seed fixed by the suggestion, so a rerun holds the
    /// same receiver.
    static func spelling(
        for suggestion: Suggestion,
        receiverExpression: ((String) -> String?)?,
        customGenerator: ((String) -> String?)?
    ) -> (String) -> String? {
        { typeName in
            if let constructed = receiverExpression?(typeName) { return constructed }
            guard let generator = customGenerator?(typeName), !generator.contains(".todo") else {
                return nil
            }
            let seed = SamplingSeed.derive(fromIdentityHash: suggestion.identity.normalized + "|receiver")
            let state = [seed.stateA, seed.stateB, seed.stateC, seed.stateD]
                .map { "0x" + String($0, radix: 16, uppercase: true) }
                .joined(separator: ", ")
            return "{ var receiverRNG = Xoshiro(seed: (\(state))); "
                + "return (\(generator)).run(using: &receiverRNG) }()"
        }
    }
}

extension Evidence {

    /// This row called on `expression` rather than on a drawn receiver: a static-looking callee
    /// whose qualifier is the expression, so `CalleeReference` renders `expression.name(args)`
    /// and counts only the method's own arguments.
    func holdingReceiver(as expression: String) -> Self {
        Self(
            displayName: displayName,
            signature: signature,
            location: location,
            isInstanceMethod: false,
            isMutatingMethod: isMutatingMethod,
            isNullary: isNullary,
            returnsSelfType: returnsSelfType,
            isComputedProperty: isComputedProperty,
            parameterTypeNames: parameterTypeNames,
            parameterInternalNames: parameterInternalNames,
            qualifiedTypeName: expression,
            globalActor: globalActor,
            declaresNonisolated: declaresNonisolated,
            genericParameters: genericParameters,
            inoutParameterIndices: inoutParameterIndices
        )
    }
}
