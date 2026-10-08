/// The CHARACTERISATION law-class banner, apart from `InteractiveTriage+StubFile.swift` for its
/// length limit.
extension InteractiveTriage {

    /// The CHARACTERISATION law-class banner. `sorted-output` names its own edits, and the one way
    /// it CAN fail today: the general wording describes `guard-domain`, and "cannot fail" is false
    /// of a comparator that is not a strict weak ordering.
    static func characterisationHeader(templateName: String) -> String {
        if templateName == "marker-dispatch" {
            return """
            // Law class: CHARACTERISATION — this law is the keyword table the subject dispatches
            //            on, read out of its own body, so a pass says little about today's
            //            behaviour. It catches an EDIT: a `||` turned `&&`, a marker dropped or
            //            misspelled, two rows reordered. Each marker is checked alone.

            """
        }
        if templateName == "sorted-output" {
            return """
            // Law class: CHARACTERISATION — this law is the comparator the subject sorts with, read
            //            out of its own body, so a pass says little about today's behaviour. It
            //            catches an EDIT: a key dropped or reordered, a direction flipped, a
            //            tie-break negated. It fails today only if the comparator is not a strict
            //            weak ordering — a real defect, since `sorted(by:)` requires one.

            """
        }
        return """
        // Law class: CHARACTERISATION — this law was READ OUT OF the subject's own body, so it
        //            cannot fail against the code it was read from and a pass says nothing
        //            about today's behaviour. It catches an EDIT: a refactor that drops the
        //            guard, reorders it after a mutation, or normalises the value it used to
        //            return untouched. Read the sentence and decide whether you meant it.

        """
    }
}
