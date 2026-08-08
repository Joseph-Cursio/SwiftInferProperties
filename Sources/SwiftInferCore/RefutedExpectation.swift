/// A refutation the reader was entitled to expect would hold.
///
/// ## Why this is not called a suspected defect
///
/// `docs/ideas/Refuted-high-confidence-guess as candidate bug.md` proposed exactly that
/// name. `docs/plans/suspected-defect-verdict-scope.md` §11 measured whether the tool can
/// earn it and the answer is no:
///
/// - The **conjecture** signal fires on **14 of 14** refutations on record — 5 real
///   defects, 9 false laws — because `commutativity`, `associativity` and `idempotence`
///   are all outside `Refutability.roleEntailedTemplates` by design.
/// - A **body-shape** reader fails worse. `Decisions.merge`'s pre-fix body composed its
///   operands positionally (`records + other.records`), which is the same shape as a
///   correct path join (`text + "/" + other.text`). It would suppress the defect and keep
///   the false law.
///
/// The distinguishing question — *is this a property the function OWES?* — is about
/// intent, and two functions can share a signature, a tier, a body shape and a
/// counterexample while answering it differently. No static signal reads intent.
///
/// So this type decides **visibility**, never blame: which refutations a reader should
/// look at first. The verdict it labels states both readings and picks neither, which is
/// the idea doc's own open question 3 promoted from preference to measured constraint.
public enum RefutedExpectation {

    /// How much of the subject's input space the run actually explored.
    ///
    /// `notApplicable` is the algebraic surface, which has no action space to
    /// under-explore: there, a `measuredDefaultFails` already means the stub compiled, ran,
    /// and failed at a numbered trial, because a trap or parse failure is `measuredError`
    /// instead. The scope note's §2.3 records that inheriting the interaction surface's
    /// coverage clause here would reject every algebraic refutation, including the four
    /// that were confirmed defects.
    public enum Coverage: Sendable, Equatable {
        case notApplicable
        case full
        case partial
    }

    /// Whether this refutation is one the reader was entitled to expect would hold.
    ///
    /// Three clauses, each corrected against a measurement in the scope note §2:
    ///
    /// 1. **Tier at least `.likely`**, via `Tier.atLeastAsProminentAs` — never an
    ///    open-coded comparison, because `Tier`'s `Comparable` puts `verified` at the
    ///    *minimum*, so the idea doc's `>= .strong` selects the low tiers.
    /// 2. **A counterexample is present.** A refutation with no rendered failing input
    ///    cannot be shown to a reader as anything, and it is the cheapest check that the
    ///    record is well-formed.
    /// 3. **Coverage is not partial.** A partial exploration can false-fail from the
    ///    action space it excluded.
    public static func statesAFork(
        tier: Tier?,
        hasCounterexample: Bool,
        coverage: Coverage
    ) -> Bool {
        guard let tier, Tier.atLeastAsProminentAs(.likely).contains(tier) else { return false }
        guard hasCounterexample else { return false }
        return coverage != .partial
    }

    /// The two readings, in the order a reader should weigh them.
    ///
    /// Rendered together and always. Presenting one without the other is the failure this
    /// whole verdict exists to avoid — in either direction: *"this is a bug"* is wrong for
    /// a path join that was never commutative, and silence is wrong for a merge fold that
    /// owes commutativity and does not deliver it.
    public static let readings = [
        "the law does not apply to this function — the guess was wrong, and that is a "
            + "finding about the guess",
        "the law does apply and the function is wrong — the guess was right, and this is "
            + "a bug"
    ]

    /// One line naming what the tool cannot settle, so the fork does not read as
    /// indecision.
    public static let disclaimer =
        "Nothing in the signature, the tier, or the counterexample separates these two: "
            + "the difference is whether the property was INTENDED to hold, which is not "
            + "in the code. Measured — see docs/plans/suspected-defect-verdict-scope.md §11."
}
