import SwiftInferCore

/// Templates the accept path writes no stub for **on purpose**, with the reason.
///
/// The generic sentence — *"no stub writeout available for template 'X' in v1"* — reads as
/// unfinished work, and for these it is not: it is a decision, measured and recorded. Saying so
/// stops a reader waiting for a writer that will not be built, which is the same point
/// `StubApplicationArity.declineReason` makes for a subject rather than a template (#456).
///
/// **Kept out of the `InteractiveTriage+Accept*` files deliberately.** `StubWriterCoverageTests`
/// reads a `case "…":` there as a writer ARM, and a decline is not one — these templates stay on
/// its `noWriterYet` list, where their entries record the decision.
enum DeliberateStubDecline {

    static func reason(forTemplate templateName: String) -> String? {
        switch templateName {
        // #478, measured in `docs/measurements/normal-form-state-machine-writers.md` §2. The law is
        // over text the parser accepts and the tool has no grammar for it: the generator the accept
        // path would hand a stub was accepted 0 times in 10,000 on the best three subjects, and of
        // the six rows whose halves share a type, five are vacuous under it. The sixth owes the
        // stronger law the template's first caveat already names.
        case "normal-form":
            return "'normal-form' writes no stub by design: its law is over text the parser accepts, "
                + "and swift-infer cannot generate that text — measured, generated strings were "
                + "accepted 0 times in 10,000 on the best subjects, so a stub would pass on nothing. "
                + "Write it by hand over inputs you know parse, and state the stronger "
                + "`print(parse(s)) == s` instead if the printer is full-fidelity"

        default:
            return nil
        }
    }
}
