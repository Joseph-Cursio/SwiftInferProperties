import SwiftInferCore

/// `@EffectUnknown` — link 3 of the chain that began with SwiftIdempotency
/// shipping a spelling for the `unknown` tier.
///
/// Split into its own file both for the 400-line cap and because the decision it
/// records is self-contained: what a tool should do when the author explicitly
/// declines to make a claim.
extension IdempotenceTemplate {

    /// `@EffectUnknown` — a caveat, deliberately, and **not** a signal.
    ///
    /// The author declared they cannot determine this function's effect. That is
    /// not a claim about the law, so it must not move the score in either
    /// direction:
    ///
    /// - **Not a veto.** `@NonIdempotent` vetoes because it *denies this exact
    ///   law*. `unknown` denies nothing; vetoing it would suppress possibly-true
    ///   laws on the strength of an author's uncertainty, and the two annotations
    ///   are not degrees of one thing — `unknown` is incomparable to
    ///   `non_idempotent`, which is why SEI reads it with its own predicate.
    /// - **Not corroboration.** Uncertainty is not evidence *for* the law either.
    ///
    /// So it earns a line, not points — the posture `StdlibAnchor` and the
    /// kit-passed provenance already take, and for the same reason. What the line
    /// buys is the thing the marker was built for: before this, a declaration
    /// saying *"I do not know"* was indistinguishable from one saying nothing.
    ///
    /// It sits among the caveats because the reader-facing content is a limit on
    /// the evidence — the shape is all there is here, and the one person who
    /// could have corroborated it explicitly declined to.
    static let unknownEffectCaveat =
        "The author declared this function's effect CANNOT be determined "
        + "(`@EffectUnknown` / `@lint.effect unknown`), so the declaration neither "
        + "supports nor denies this law — the shape is the only evidence. Unlike "
        + "`@NonIdempotent`, which would deny it outright, this is an open question "
        + "the author did not resolve, which is where checking the property earns "
        + "the most."
}
