import Foundation
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
    static func entailedTemplateStub(for suggestion: Suggestion) -> String? {
        switch suggestion.templateName {
        // Both state the same law — the subject returns or throws for every input its parameter
        // type admits — so one arm serves them. `predicate` calls it the only free law a bare
        // `Bool`-returning function carries; `input-totality` calls it the law a fuzz harness
        // asserts, reached without needing one to exist.
        case "predicate", "input-totality":
            return totalityStub(for: suggestion)

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
    private static func totalityStub(for suggestion: Suggestion) -> String? {
        guard let evidence = suggestion.evidence.first,
              let callee = CalleeReference(evidence: evidence),
              let arity = StubApplicationArity.forTemplate(suggestion.templateName),
              callee.accepts(applicationArity: arity),
              let typeName = paramType(from: evidence.signature) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.total(
            callee: callee,
            seed: seed,
            // Not `chooseGenerator` — totality is the one law in the catalog whose
            // counterexamples live outside the domain the shared generator draws from.
            generator: LiftedTestEmitter.hostileGenerator(for: typeName),
            isThrowing: evidence.signature.contains(" throws"),
            isAsync: evidence.signature.contains(" async")
        )
    }
}
