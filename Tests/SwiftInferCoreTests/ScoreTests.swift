import Testing
@testable import SwiftInferCore

@Suite("Score — signal aggregation and veto handling")
struct ScoreTests {

    @Test("Empty signals total to zero and land in suppressed")
    func emptySignals() {
        let score = Score(signals: [])
        #expect(score.total == 0)
        #expect(score.tier == .suppressed)
        #expect(!score.isVetoed)
    }

    @Test("Sums non-veto weights and maps to tier")
    func sumsNonVetoWeights() {
        let signals = [
            Signal(kind: .typeSymmetrySignature, weight: 30, detail: "type sym"),
            Signal(kind: .exactNameMatch, weight: 40, detail: "name"),
            Signal(kind: .selfComposition, weight: 20, detail: "comp")
        ]
        let score = Score(signals: signals)
        #expect(score.total == 90)
        #expect(score.tier == .strong)
        #expect(!score.isVetoed)
    }

    @Test("Negative non-veto weights are subtracted from total")
    func negativeWeightsApply() {
        let signals = [
            Signal(kind: .typeSymmetrySignature, weight: 30, detail: "type sym"),
            Signal(kind: .exactNameMatch, weight: 40, detail: "name"),
            Signal(kind: .partialFunction, weight: -15, detail: "guard")
        ]
        let score = Score(signals: signals)
        #expect(score.total == 55)
        #expect(score.tier == .likely)
    }

    @Test("Veto signal collapses tier to suppressed regardless of total")
    func vetoCollapsesTier() {
        let signals = [
            Signal(kind: .typeSymmetrySignature, weight: 30, detail: "type sym"),
            Signal(kind: .exactNameMatch, weight: 40, detail: "name"),
            Signal(kind: .nonDeterministicBody, weight: Signal.vetoWeight, detail: "Date()")
        ]
        let score = Score(signals: signals)
        // total reflects the non-veto sum so diagnostic rendering can still
        // show "would have scored 70 but was vetoed" if needed later.
        #expect(score.total == 70)
        #expect(score.isVetoed)
        #expect(score.tier == .suppressed)
    }

    @Test("Signal.vetoWeight is the sentinel marker, not a summed weight")
    func vetoWeightSentinel() {
        let veto = Signal(kind: .nonEquatableOutput, weight: Signal.vetoWeight, detail: "x")
        #expect(veto.isVeto)
        let nonVeto = Signal(kind: .partialFunction, weight: -15, detail: "x")
        #expect(!nonVeto.isVeto)
    }
}
