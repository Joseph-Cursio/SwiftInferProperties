import Foundation
import SwiftInferCore

/// How many arguments each template's property expression applies to its subject.
///
/// ## Why this is a table and not a literal at each call site
///
/// Two things need the number and must agree: the stub builder, which declines a subject that
/// cannot be called with that many, and the diagnostic, which tells the reader *why* nothing was
/// written. Two copies of one number is the drift this codebase keeps recording — the
/// `parallel-list-drift` note on `RawType` is the same hazard seen from the other side. So the
/// builders read it here, and so does the decline.
///
/// ## What the number means
///
/// It counts the arguments the *law* applies, not the parameters the function declares.
/// `idempotence` states `f(f(x)) == f(x)` and applies one; `commutativity` states
/// `f(a, b) == f(b, a)` and applies two. A subject fits when
/// `CalleeReference.applicationArity` equals it — and for an instance method that arity includes
/// the receiver, which is what makes a one-parameter instance method fit commutativity and not
/// idempotence.
///
/// `replay-idempotence` is deliberately absent: it emits a `.todo` scaffold through a different
/// path that never builds a `CalleeReference`, so it has no arity to state here.
enum StubApplicationArity {

    static func forTemplate(_ templateName: String) -> Int? {
        switch templateName {
        case "idempotence", "round-trip", "monotonicity", "invariant-preservation", "inverse-pair",
             "predicate", "input-totality":
            return 1

        case "commutativity", "associativity", "identity-element":
            return 2

        default:
            return nil
        }
    }

    /// Why this suggestion's subject cannot be called by its template, or `nil` when it can.
    ///
    /// **Kept apart from "no stub writeout available for this template".** That sentence was the
    /// only thing a reader saw for every un-emitted suggestion, and for a declined subject it is
    /// false: the template has a writeout, and it is the subject that cannot be spelled. Measured
    /// on SwiftMarkdownWiki after the call-shape fix, 7 of 7 declines were subjects rather than
    /// templates — so the one message was wrong every time it fired.
    static func declineReason(for suggestion: Suggestion) -> String? {
        guard let arity = forTemplate(suggestion.templateName),
              let evidence = suggestion.evidence.first else {
            return nil
        }
        guard let callee = CalleeReference(evidence: evidence) else {
            return "\(evidence.displayName) is a mutating method, so it returns no value for the law to compare"
        }
        guard !callee.accepts(applicationArity: arity) else { return nil }
        let needs = callee.applicationArity
        let receiver = callee.isInstanceMethod ? " (a receiver plus \(needs - 1))" : ""
        return "\(callee.displaySignature) needs \(needs) argument\(needs == 1 ? "" : "s")\(receiver), "
            + "but '\(suggestion.templateName)' applies \(arity)"
    }
}
