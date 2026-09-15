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
///
/// ## The templates with no number
///
/// `predicate` and `input-totality` state **totality**, which calls the subject once and discards
/// the result. It composes nothing and compares nothing, so no arity is part of the law: it is
/// well-formed at any application arity of one or more. They were in the arity-1 row until #464,
/// and the corpus funnel census measured what that cost — **497 entailed laws declined**, 427 of
/// them instance methods, the largest single loss it found.
enum StubApplicationArity {

    static func forTemplate(_ templateName: String) -> Int? {
        switch templateName {
        case "idempotence", "round-trip", "monotonicity", "invariant-preservation", "inverse-pair":
            return 1

        case "commutativity", "associativity", "identity-element":
            return 2

        default:
            return nil
        }
    }

    /// Templates whose law holds at every application arity of one or more.
    static let arityFreeTemplates: Set<String> = ["predicate", "input-totality"]

    /// Why this suggestion's subject cannot be called by its template, or `nil` when it can.
    ///
    /// **Kept apart from "no stub writeout available for this template".** That sentence was the
    /// only thing a reader saw for every un-emitted suggestion, and for a declined subject it is
    /// false: the template has a writeout, and it is the subject that cannot be spelled. Measured
    /// on SwiftMarkdownWiki after the call-shape fix, 7 of 7 declines were subjects rather than
    /// templates — so the one message was wrong every time it fired.
    static func declineReason(for suggestion: Suggestion) -> String? {
        let isArityFree = arityFreeTemplates.contains(suggestion.templateName)
        let arity = forTemplate(suggestion.templateName)
        guard isArityFree || arity != nil, let evidence = suggestion.evidence.first else {
            return nil
        }
        guard let callee = CalleeReference(evidence: evidence) else {
            return "\(evidence.displayName) is a mutating method, so it returns no value for the law to compare"
        }
        // **A carrier the emitter cannot name is its own cause, and used to read as a missing
        // template arm.** `paramType` answers for a parameterised subject and `qualifiedTypeName`
        // for a receiver-form one; a free nullary function has neither, and the law has nothing
        // to quantify over. Saying so is the difference between a reader looking at their
        // signature and looking for a tool that does not exist (#456).
        if InteractiveTriage.carrierType(for: evidence) == nil {
            return "\(evidence.displayName) has no parameter and no enclosing type, so there is "
                + "no value for the law to quantify over"
        }
        guard let arity else { return arityFreeDeclineReason(callee: callee, evidence: evidence) }
        // A paired template needs both halves. One evidence row means the pair was never
        // resolved, which is a fact about the SUBJECT rather than about the emitter.
        if ["round-trip", "inverse-pair", "identity-element"].contains(suggestion.templateName),
           suggestion.evidence.count < 2 {
            return "'\(suggestion.templateName)' needs two subjects and this suggestion carries "
                + "one, so the pair was never resolved"
        }
        // `monotonicity` sorts a drawn pair with `<`. An Optional carrier cannot be ordered, and
        // the compiler reports it as an inference failure on the closure parameter — so saying so
        // here is the difference between a reader looking at optionality and looking at the
        // template. Same split as the arity reasons below.
        if suggestion.templateName == "monotonicity",
           let carrier = InteractiveTriage.paramType(from: evidence.signature),
           FloatingPointEquatableTypes.isOrderableCarrier(typeText: carrier) == false {
            return "\(evidence.displayName) takes \(carrier), and 'monotonicity' orders its "
                + "drawn pair with `<` — an Optional is not Comparable"
        }
        guard !callee.accepts(applicationArity: arity) else { return nil }
        let needs = callee.applicationArity
        let receiver = callee.isInstanceMethod ? " (a receiver plus \(needs - 1))" : ""
        return "\(callee.displaySignature) needs \(needs) argument\(needs == 1 ? "" : "s")\(receiver), "
            + "but '\(suggestion.templateName)' applies \(arity)"
    }

    /// Why a totality subject cannot be written, or `nil` when it can — the questions an
    /// arity-free law still has to ask once the number is gone.
    ///
    /// Kept in step with `InteractiveTriage.totalityArgumentTypes`, which declines exactly these;
    /// `ArityFreeTotalityTests` pins both sides of every row.
    private static func arityFreeDeclineReason(callee: CalleeReference, evidence: Evidence) -> String? {
        // A static computed property or a static nullary function is called with nothing, so
        // there is no input for "every input" to range over.
        if callee.applicationArity == 0 {
            return "\(callee.displaySignature) takes no arguments, so there is no input for totality "
                + "to range over"
        }
        // An instance method's receiver is drawn from its declaring type; with none recorded
        // there is nothing to draw it from.
        if callee.isInstanceMethod, evidence.qualifiedTypeName == nil {
            return "\(callee.displaySignature) is an instance method with no recorded enclosing type, "
                + "so there is no receiver to draw"
        }
        let parameters = InteractiveTriage.parameterTypes(from: evidence.signature)
        if parameters.contains(where: { $0.hasPrefix("inout ") }) {
            return "\(callee.displaySignature) takes an `inout` parameter, and a drawn value is "
                + "immutable, so the call cannot be spelled"
        }
        if parameters.count != callee.argumentLabels.count {
            return "\(callee.displaySignature) records \(callee.argumentLabels.count) argument "
                + "label(s) and \(parameters.count) parameter type(s), so the call cannot be spelled "
                + "reliably"
        }
        return nil
    }
}
