import Foundation

/// The **corroboration rule** — a prototype, behind a flag, for a defect Q3 measured rather
/// than argued.
///
/// ## What Q3 found
///
/// On denominator A, `discover` reached 9 of 12 laws — and **all nine rested on a single
/// signal**: *"declares a custom `Codable` conformance"*, `+50`, on every one, scoring exactly
/// 50 (Likely). Unique contribution of the conformance channel: 9/9. Of shape, name and
/// docstring: zero. Remove that one signal and every hit goes `50 → 0`, Suppressed.
///
/// That is uncomfortable for a *type-directed inference* tool: on the denominator where it
/// succeeds, the success comes from reading a conformance declaration — the one channel
/// `fixtures/equatable-signal/README.md` already measured and found **does not predict
/// refutability**.
///
/// ## Why a count, and why two
///
/// A suggestion carrying one signal has a score that *is* that signal's weight; the number
/// carries no information beyond which signal fired. Measured corpus-wide: **74%** of
/// swift-syntax suggestions (820 of 1,115) and **49%** of `stdlib/public/core` (363 of 745)
/// carry exactly one. Requiring a second independent channel is the smallest change that makes
/// the score mean *"several things agree"* rather than *"one thing fired"*.
///
/// ## Deliberately a prototype
///
/// This does **not** touch `Tier.init(forScore:)`. The repo's standing rule is that the tier
/// arithmetic is not adjusted to reach a target — the carve-outs live in the consumers. So the
/// rule is a **visibility** predicate applied at the display cut, opt-in, and measurable by
/// running with and without it.
///
/// **The trade is known and is the point of measuring it.** On `stdlib/public/core` it demotes
/// 52 of 176 default-visible suggestions, 47 of them `codable-round-trip` — i.e. it demotes
/// exactly the family Q3's recall was made of, taking that 75% to roughly zero. On swift-syntax
/// it demotes **0 of 24** and costs nothing. Whether that trade is right is a judgement about
/// how much a lone conformance declaration is worth, and this exists so the judgement can be
/// made against numbers.
public enum CorroborationRule {

    /// How many independent positive channels a suggestion must have to keep its
    /// default-visible tier under the rule.
    public static let requiredChannels = 2

    /// Positive, score-contributing signals. Counter-signals and vetoes are excluded: they
    /// argue *against* the law, so they cannot corroborate it.
    ///
    /// **A deliberate simplification, stated rather than hidden.** "Independent" is taken to
    /// mean "a distinct positive signal", not "provably uncorrelated evidence". Two signals
    /// from one template can share a root cause — `typeSymmetrySignature` and `exactNameMatch`
    /// usually co-fire on the same declaration. A stricter reading would key on
    /// `Signal.Kind` *families* (shape / name / prose / annotation / conformance), and that is
    /// the obvious next refinement if the coarse version measures well.
    public static func positiveChannelCount(_ score: Score) -> Int {
        score.signals.filter { $0.weight > 0 }.count
    }

    /// `true` when the suggestion has enough independent positive evidence to stay visible by
    /// default under the rule.
    public static func isCorroborated(_ score: Score) -> Bool {
        positiveChannelCount(score) >= requiredChannels
    }
}
