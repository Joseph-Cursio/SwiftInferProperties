@testable import SwiftInferCore
import Testing

/// The corroboration rule — a prototype that exists to make a design question **measurable**
/// rather than arguable.
///
/// Q3 measured that all nine laws `discover` reached rested on a single `+50` conformance
/// signal, and that 74% of swift-syntax suggestions carry exactly one signal at all. This rule
/// withholds default visibility from single-signal suggestions. Measured cost, blinded:
///
/// | corpus | default | with the rule |
/// |---|---|---|
/// | swift-syntax | 586 | **586** — free |
/// | `stdlib/public/core` | 315 | 264 (−16%) |
/// | swift-foundation | 347 | 259 (−25%) |
/// | **Q3 recall** | **9/12** | **0/12** |
///
/// That last row is the whole point: the rule demotes precisely the family Q3's recall was
/// made of. Whether that is right is a judgement about how much a lone conformance
/// declaration is worth, and it should be made against these numbers.
@Suite("Corroboration rule — a second channel to keep default visibility")
struct CorroborationRuleTests {

    private func score(_ weights: [Int]) -> Score {
        Score(signals: weights.enumerated().map { index, weight in
            Signal(kind: .exactNameMatch, weight: weight, detail: "signal \(index)")
        })
    }

    @Test("a single positive signal is not corroborated")
    func singleSignalIsNotCorroborated() {
        #expect(!CorroborationRule.isCorroborated(score([50])))
        #expect(CorroborationRule.positiveChannelCount(score([50])) == 1)
    }

    @Test("two positive signals are")
    func twoSignalsAreCorroborated() {
        #expect(CorroborationRule.isCorroborated(score([40, 30])))
    }

    /// The Q3 shape exactly: `codable-round-trip` at 50, one `+50` conformance signal. A high
    /// score is NOT corroboration — that is the distinction the rule exists to draw, and the
    /// reason it cannot be expressed as a threshold change.
    @Test("a HIGH score on one signal is still uncorroborated")
    func highScoreDoesNotSubstituteForASecondChannel() {
        let q3Shape = score([50])
        #expect(q3Shape.total == 50)
        #expect(q3Shape.tier == .likely, "shown by default without the rule")
        #expect(!CorroborationRule.isCorroborated(q3Shape))
    }

    /// Counter-signals argue *against* the law, so they cannot corroborate it. Without this,
    /// a single positive signal plus a penalty would read as two channels and pass.
    @Test("counter-signals do not count as corroboration")
    func negativeSignalsDoNotCorroborate() {
        let withPenalty = Score(signals: [
            Signal(kind: .exactNameMatch, weight: 50, detail: "name"),
            Signal(kind: .crossTypeRoundTripPair, weight: -25, detail: "counter")
        ])
        #expect(CorroborationRule.positiveChannelCount(withPenalty) == 1)
        #expect(!CorroborationRule.isCorroborated(withPenalty))
    }

    @Test("a zero-weight signal is not a channel either")
    func zeroWeightIsNotAChannel() {
        let padded = Score(signals: [
            Signal(kind: .exactNameMatch, weight: 40, detail: "name"),
            Signal(kind: .samplingPass, weight: 0, detail: "informational")
        ])
        #expect(!CorroborationRule.isCorroborated(padded))
    }

    @Test("the threshold is two, and it is named rather than inlined")
    func requiredChannelsIsExplicit() {
        #expect(CorroborationRule.requiredChannels == 2)
        #expect(!CorroborationRule.isCorroborated(score([10])))
        #expect(CorroborationRule.isCorroborated(score([10, 10])))
        #expect(CorroborationRule.isCorroborated(score([10, 10, 10])))
    }
}
