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

    /// A carrier that is a **caseless enum** — a namespace, not a value.
    ///
    /// Swift does not permit adding cases to an enum in an extension, so
    /// `kind == .enum && enumCases.isEmpty` is not "cases we failed to read", it is
    /// definitively a type with **no inhabitants**. No generator can exist, and telling a
    /// reader to write `static func gen() -> Generator<Namespace, _>` asks for a function
    /// that cannot return.
    ///
    /// **Measured (`roadtest-self-dogfood-2026-08-08.md` §9.9):**
    /// `SamplingSeed.derive(fromIdentityHash:)` reported `unsupported-carrier: SamplingSeed`,
    /// which reads as a generator gap and is not one. `SamplingSeed` is
    /// `public enum SamplingSeed { public struct Value { … } ; public static func … }` — the
    /// containing type of a `static` function, and `RoundTripTemplate` takes
    /// `forward.containingTypeName` as its carrier. That is right for an INSTANCE method,
    /// where the containing type is the value being round-tripped, and wrong for a static on
    /// a namespace.
    ///
    /// **Why this declines rather than re-attributing.** The obvious repair — use the
    /// forward function's parameter type — is ambiguous for a round trip, which has two
    /// legitimate carriers depending on which direction the stub runs (`g(f(a)) == a`
    /// generates `A`; `f(g(b)) == b` generates `B`). "A caseless enum has no values" needs no
    /// such choice and cannot be wrong. Re-attribution stays open, and would supersede this.
    ///
    /// **The enum-cases field must be populated for this to be sound.** It was dropped from
    /// the index once, and an enum whose cases had gone missing would look caseless here —
    /// see `IndexedTypeShape.EnumCase`, which records that bug and its fix. If that
    /// regresses, this arm turns a hung verifier into a silent decline, which is quieter but
    /// no more correct.
    public static func caselessEnumCarrier(_ shape: IndexedTypeShape?) -> String? {
        guard let shape, shape.kind == .enum, shape.enumCases.isEmpty else { return nil }
        return "carrier `\(shape.name)` is a caseless enum — a namespace with no values, "
            + "so no generator can exist for it"
    }

    /// The reason to record for an entry, or `nil` when nothing structural blocks it.
    ///
    /// Returns the signal's own `detail` rather than a re-spelling: the counter
    /// wrote the sentence, and a second wording would drift from it.
    public static func reason(among signals: [Signal]) -> String? {
        signals.first { blockingKinds.contains($0.kind) }?.detail
    }
}
