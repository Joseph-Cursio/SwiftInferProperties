/// The text of a **NOT APPLIED** note: a check that ran, passed, and cannot vouch for part of its
/// subject because no draw reached that part.
///
/// One author for the reach test's notes (#665 4b), so the funnel's harness reads one shape:
/// `scripts/corpus_funnel_stage5.py` sorts a reach warning by the side its first line names, with
/// `^NOT APPLIED — the (true|false) side: `. A note in any other shape lands in `reach_other`, which
/// #665 §9 counts as an emitter defect.
///
/// `guard-domain`'s coverage note and the entailed laws' transitivity note predate this and keep
/// their own text. Moving them here is deferred (#665 §10): it reopens when a third emitter writes a
/// NOT APPLIED note of its own.
enum NotApplied {

    /// The note a reach test records when `trials` draws never made the subject return `side`.
    ///
    /// The sentence names the law test whose pass it qualifies, because that test is green and the
    /// note is what says the green covers only one answer. The remedy offers deletion as well as a
    /// wider generator, because some predicates cannot reach the other answer from any value of
    /// their argument types (#665 §6.1's never-written receiver). For those the note is true and
    /// stays, and deleting the test is the right response.
    static func reachSide(_ side: Bool, subject: String, lawTest: String, trials: Int) -> String {
        reachSideClauses(side, subject: subject, lawTest: lawTest, trials: trials).joined()
    }

    /// `reachSide`'s text in the three pieces a stub writes it as, one string literal each, which keeps
    /// the call inside 120 columns for a subject of ordinary length. Joined, they are the note exactly.
    static func reachSideClauses(_ side: Bool, subject: String, lawTest: String, trials: Int) -> [String] {
        [
            "NOT APPLIED — the \(side) side: no draw made \(subject) return \(side) in \(trials) trials ",
            "re-drawn from \(lawTest)'s seed, so its pass says nothing about the inputs where it does. ",
            "Widen the generator to reach one, or delete this test.",
        ]
    }
}
