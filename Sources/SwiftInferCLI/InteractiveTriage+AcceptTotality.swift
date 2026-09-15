import Foundation
import PropertyLawCore
import SwiftInferCore
import SwiftInferTemplates

/// The accept-path arms for the catalog's **role-entailed** templates — the laws a correct
/// implementation cannot fail.
///
/// Split out of `InteractiveTriage+Accept.swift` for its length limit, as
/// `+AcceptAlgebraicStubs` was, and grouped by refutability rather than by shape because that is
/// the distinction that mattered: **before this file existed, 0 of 23 role-entailed suggestions
/// on SwiftMarkdownWiki produced a stub, against 21 of 25 conjectural ones.**
extension InteractiveTriage {

    /// A stub for a role-entailed template, or `nil` when the suggestion carries none.
    ///
    /// `customGenerator` derives a generator for a project type from its parsed shape — the same
    /// resolver the determinism arm uses — and matters here because a receiver is almost always
    /// a project type.
    static func entailedTemplateStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)? = nil
    ) -> String? {
        switch suggestion.templateName {
        // Both state the same law — the subject returns or throws for every input its parameter
        // type admits — so one arm serves them. `predicate` calls it the only free law a bare
        // `Bool`-returning function carries; `input-totality` calls it the law a fuzz harness
        // asserts, reached without needing one to exist.
        case "predicate", "input-totality":
            return totalityStub(for: suggestion, customGenerator: customGenerator)

        default:
            return nil
        }
    }

    /// Totality, for `predicate` and `input-totality`.
    ///
    /// **These are the catalog's role-entailed laws and not one of them was ever written out.**
    /// Measured on SwiftMarkdownWiki before this arm existed: of 48 suggestions, the 23 carried by
    /// role-entailed templates produced **0** stubs, while 21 of 25 conjectural ones produced a
    /// file. The tool emitted the laws a correct implementation can fail and declined the ones it
    /// cannot — the exact inverse of `Refutability.isWorthSurfacingBelowCut`, which exists to
    /// privilege the entailed ones.
    ///
    /// Totality needs no `Equatable` on the return type, because it compares nothing. That is why
    /// it reaches subjects the comparison-shaped arms cannot.
    ///
    /// ## Every arity, the receiver first (#464)
    ///
    /// It also needs no particular arity — it calls once — so an instance method draws its
    /// receiver and each of its parameters, and a multi-parameter function draws one value per
    /// parameter. Held to arity 1, this arm declined 497 entailed laws in the corpus funnel
    /// census, while verify's predicate composer already drew receiver and parameters.
    private static func totalityStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)?
    ) -> String? {
        guard let evidence = suggestion.evidence.first,
              let callee = CalleeReference(evidence: evidence),
              let argumentTypes = totalityArgumentTypes(callee: callee, evidence: evidence) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.total(
            callee: callee,
            seed: seed,
            generators: argumentTypes.map { totalityGenerator(for: $0, customGenerator: customGenerator) },
            isThrowing: evidence.signature.contains(" throws"),
            isAsync: evidence.signature.contains(" async")
        )
    }

    /// The type of each argument the call needs, in order — the **declaring** type for an
    /// instance method's receiver, then each parameter — or `nil` when the call cannot be spelled.
    ///
    /// The receiver is the declaring type and not the carrier, the rule verify's predicate
    /// composer settled first (`theReceiverTypeIsTheDeclaringTypeNotTheCarrier`).
    ///
    /// Declines exactly what `StubApplicationArity.arityFreeDeclineReason` explains, so a reader
    /// is never told "no stub writeout available" for a subject that simply cannot be called.
    static func totalityArgumentTypes(callee: CalleeReference, evidence: Evidence) -> [String]? {
        guard callee.applicationArity > 0 else { return nil }
        let parameters = parameterTypes(from: evidence.signature)
        guard parameters.count == callee.argumentLabels.count,
              parameters.allSatisfy({ $0.hasPrefix("inout ") == false }) else {
            return nil
        }
        guard callee.isInstanceMethod else { return parameters }
        guard let receiver = evidence.qualifiedTypeName else { return nil }
        return [receiver] + parameters
    }

    /// The generator for one argument of a totality call.
    ///
    /// **A raw stdlib type keeps the hostile generator, and that is checked first rather than
    /// left to the resolver's silence.** Totality is the one law whose counterexamples live
    /// outside the domain the shared generator draws from — measured 6 of 6 trap classes caught
    /// against 3 of 6 (`docs/measurements/totality-generator-reach.md`) — and a project that
    /// extends `String` could give the resolver a shape to answer with. A project type the
    /// resolver can build gets that. Anything else falls through the hostile generator to the
    /// kit's defaults and past those to the `.todo` marker, so a receiver nothing can build
    /// still says on its own line what to write.
    private static func totalityGenerator(
        for typeName: String,
        customGenerator: ((String) -> String?)?
    ) -> String {
        if RawType(typeName: typeName) == nil, let derived = customGenerator?(typeName) {
            return derived
        }
        return LiftedTestEmitter.hostileGenerator(for: typeName)
    }
}
