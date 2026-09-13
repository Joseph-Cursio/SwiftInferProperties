import Foundation
import SwiftInferCore

/// What the accept path says when it writes nothing.
///
/// Split out of `InteractiveTriage+Accept.swift` when #415's decline rule took that file past
/// SwiftLint's 400-line cap — same overflow convention as the `+AcceptAlgebraicStubs` /
/// `+AcceptConformance` files beside it.
extension InteractiveTriage {

    /// Why no file was written — **two causes, kept apart**.
    ///
    /// The single note this replaced said *no stub writeout available for template X in v1*
    /// for both, and the two are nothing alike: one is a template with no emitter arm yet, the
    /// other is a subject this catalogue can state a law about but cannot CALL from a stub.
    /// Conflating them makes the second invisible, and the second is the one #415 added — so
    /// it is also the number an A/B of that change has to count.
    static func noStubNote(for suggestion: Suggestion) -> String {
        if let evidence = suggestion.evidence.first,
           evidence.isInstanceMethod,
           StubCallShape.callExpression(
               for: evidence, applicationArity: applicationArity(of: suggestion.templateName)
           ) == nil {
            return "note: \(evidence.displayName) is an instance method whose receiver the"
                + " '\(suggestion.templateName)' stub cannot supply — a law about it would have"
                + " to be called on a value this template never draws. Decision recorded"
                + " without writing a file"
        }
        return "note: no stub writeout available for template '\(suggestion.templateName)' in v1; "
            + "decision recorded without writing a file"
    }

    /// How many arguments a template's property expression applies. See `StubCallShape` for why
    /// an instance method's receiver makes this the deciding number.
    static func applicationArity(of templateName: String) -> Int {
        switch templateName {
        case "commutativity", "associativity", "identity-element":
            return 2

        default:
            return 1
        }
    }
}
