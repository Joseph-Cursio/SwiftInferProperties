@testable import SwiftInferCore
import Testing

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

    @Test("Verified, Strong, Likely, and Advisory are visible by default; Possible and Suppressed are not")
    func defaultVisibility() {
        #expect(Tier.verified.isVisibleByDefault)
        #expect(Tier.strong.isVisibleByDefault)
        #expect(Tier.likely.isVisibleByDefault)
        #expect(!Tier.possible.isVisibleByDefault)
        #expect(!Tier.suppressed.isVisibleByDefault)
        #expect(Tier.advisory.isVisibleByDefault)
    }

    @Test("Tier labels match the explainability-block header strings")
    func labelText() {
        #expect(Tier.verified.label == "Verified")
        #expect(Tier.strong.label == "Strong")
        #expect(Tier.likely.label == "Likely")
        #expect(Tier.possible.label == "Possible")
        #expect(Tier.suppressed.label == "Suppressed")
        #expect(Tier.advisory.label == "Advisory")
    }

    @Test("Tier(score:) never returns .advisory or .verified — both are set explicitly by the surfacing pipeline")
    func scoreInitNeverReturnsPipelineOnlyTiers() {
        for score in stride(from: -100, through: 200, by: 13) {
            #expect(Tier(score: score) != .advisory)
            #expect(Tier(score: score) != .verified)
        }
    }

    /// Regression guard — `Tier`'s severity order is load-bearing:
    /// `MetricsRenderer` renders metric-table rows in `Tier`'s
    /// `Comparable` order (`Tier.allCases.sorted()`). That order is
    /// defined explicitly by `Tier.severityRank`, not by `case`-line
    /// layout — so the `case` lines are now free to be reordered, but
    /// editing `severityRank` silently changes `swift-infer metrics`
    /// output. If this turns red, the rank change is the bug.
    @Test("Tier's Comparable order is verified → strong → likely → possible → suppressed → advisory")
    func comparableOrder() {
        #expect(Tier.allCases.sorted() == [.verified, .strong, .likely, .possible, .suppressed, .advisory])
    }

    // MARK: - V1.65 promoted(byVerifyOutcome:)

    @Test(".strong promotes to .verified only on .measuredBothPass evidence")
    func strongPromotesOnlyOnBothPass() {
        #expect(Tier.strong.promoted(byVerifyOutcome: .measuredBothPass) == .verified)
        #expect(Tier.strong.promoted(byVerifyOutcome: .measuredEdgeCaseAdvisory) == .strong)
        #expect(Tier.strong.promoted(byVerifyOutcome: .measuredDefaultFails) == .strong)
        #expect(Tier.strong.promoted(byVerifyOutcome: .measuredError) == .strong)
        #expect(Tier.strong.promoted(byVerifyOutcome: .architecturalCoveragePending) == .strong)
        #expect(Tier.strong.promoted(byVerifyOutcome: nil) == .strong)
    }

    @Test("non-.strong tiers never promote, even on .measuredBothPass")
    func nonStrongTiersNeverPromote() {
        for base: Tier in [.verified, .likely, .possible, .suppressed, .advisory] {
            #expect(base.promoted(byVerifyOutcome: .measuredBothPass) == base)
            #expect(base.promoted(byVerifyOutcome: nil) == base)
        }
    }
}
