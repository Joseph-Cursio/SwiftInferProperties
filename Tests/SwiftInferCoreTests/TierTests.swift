import Testing
@testable import SwiftInferCore

@Suite("Tier — score-to-tier boundary mapping")
struct TierTests {

    @Test("Score >= 75 is Strong")
    func scoreAtAndAboveStrongThreshold() {
        #expect(Tier(score: 75) == .strong)
        #expect(Tier(score: 95) == .strong)
        #expect(Tier(score: 1_000) == .strong)
    }

    @Test("Score 40..74 is Likely")
    func scoreInLikelyBand() {
        #expect(Tier(score: 40) == .likely)
        #expect(Tier(score: 60) == .likely)
        #expect(Tier(score: 74) == .likely)
    }

    @Test("Score 20..39 is Possible")
    func scoreInPossibleBand() {
        #expect(Tier(score: 20) == .possible)
        #expect(Tier(score: 30) == .possible)
        #expect(Tier(score: 39) == .possible)
    }

    @Test("Score < 20 is Suppressed")
    func scoreBelowVisibleThreshold() {
        #expect(Tier(score: 19) == .suppressed)
        #expect(Tier(score: 0) == .suppressed)
        #expect(Tier(score: -100) == .suppressed)
    }

    @Test("Strong and Likely are visible by default; Possible and Suppressed are not")
    func defaultVisibility() {
        #expect(Tier.strong.isVisibleByDefault)
        #expect(Tier.likely.isVisibleByDefault)
        #expect(!Tier.possible.isVisibleByDefault)
        #expect(!Tier.suppressed.isVisibleByDefault)
    }

    @Test("Tier labels match the explainability-block header strings")
    func labelText() {
        #expect(Tier.strong.label == "Strong")
        #expect(Tier.likely.label == "Likely")
        #expect(Tier.possible.label == "Possible")
        #expect(Tier.suppressed.label == "Suppressed")
    }
}
