/// A signal that already knows the property **cannot be measured**, for a reason
/// that has nothing to do with whether a generator exists for the carrier.
///
/// ## Why this is a separate concept from a low score
///
/// Some counters demote a suggestion because it is *unlikely*. A few demote it
/// because the law, as paired, **cannot type-check** — the shape is wrong, not the
/// confidence. `verify` finds that out by trying, and then reports whatever error
/// it happens to hit first, which is not the reason.
///
/// Measured 2026-08-05: all 45 cross-module `round-trip` pairs in this repo's index
/// were filed as `unsupported-carrier: <CarrierName>` — *no generator derives this
/// carrier*. That reads as a **carrier-reach gap**, and it is not one: even a
/// perfect generator would not make `PeerProposal.canonicalLawName` resolve, because
/// the inverse half lives on a different type in a different module. The carrier is
/// beside the point.
///
/// **The cost of that mislabelling is demonstrated, not hypothetical.** It is what
/// produced the claim *"round-trip's zero is carrier reach"* in the whole-corpus
/// survey write-up, and a proposal to spend effort on generators. A census that
/// misattributes 45 rows to reach points work at the wrong constraint — the same
/// failure `docs/measurements/verify-carrier-reach-census.md` records for a different cause
/// (*"a census that forgets to thread `allShapes` invents a carrier problem
/// two-thirds of which is the harness"*).
///
/// ## What this deliberately does NOT do
///
/// It does not suppress the row, change its score, or save any build. **Nothing
/// builds for these entries today** — `buildStubBundle` throws before
/// `runSwiftBuild` is reached, so the survey already declines them for free. The
/// only thing that changes is *which reason the census records*, which is the whole
/// value: an honest denominator, not a faster run.
///
/// ## Adding a case
///
/// The bar is that the signal makes the property **unstatable as paired**, not
/// merely improbable. A counter that means "probably wrong" belongs in the score,
/// where a reader can overrule it; this list is for shapes where trying is
/// pointless. Keep it short — every entry here is a claim that verify's own error
/// would have been less informative.
public enum StructuralBlocker {

    /// Signal kinds whose firing means the law cannot type-check as paired.
    ///
    /// One member today, and it earned its place by measurement rather than by
    /// argument. `crossTypeRoundTripPair`'s own detail string already states the
    /// conclusion — *"property cannot type-check across distinct containing
    /// types"* — so this is only carrying a verdict that already existed as far as
    /// the thing that needed it.
    /// `subjectNotVisibleToTests` joined on 2026-08-09 and meets the bar in the strictest
    /// way available: the law is not merely unlikely to type-check, the test target cannot
    /// NAME the symbol. `discover` already said so in prose — *"NO TEST CAN RUN THIS LAW AS
    /// WRITTEN"* — and `verify` built the stub anyway and filed the result as `build-failed`,
    /// an instrument-failure bucket for a fact known before the build started (§9.2 of
    /// `docs/measurements/roadtest-self-dogfood-2026-08-08.md`).
    ///
    /// It changes the recorded REASON, not the outcome: these entries decline either way.
    /// That is the same contribution `crossTypeRoundTripPair` makes and the same one this
    /// type's doc calls the whole value — an honest denominator.
    static let blockingKinds: Set<Signal.Kind> = [.crossTypeRoundTripPair, .subjectNotVisibleToTests]

    /// The reason to record for an entry, or `nil` when nothing structural blocks it.
    ///
    /// Returns the signal's own `detail` rather than a re-spelling: the counter
    /// wrote the sentence, and a second wording would drift from it.
    public static func reason(among signals: [Signal]) -> String? {
        signals.first { blockingKinds.contains($0.kind) }?.detail
    }
}
