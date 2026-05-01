import Testing
@testable import SwiftInferCore

@Suite("Signal — formattedLine bullet text (M4.4)")
struct SignalTests {

    @Test
    func positiveWeightRendersWithPlusPrefix() {
        let signal = Signal(kind: .exactNameMatch, weight: 40, detail: "Curated commutativity verb match: 'merge'")
        #expect(signal.formattedLine == "Curated commutativity verb match: 'merge' (+40)")
    }

    @Test
    func zeroWeightStillCarriesPlusPrefix() {
        // Edge case — `+` is the sign for non-negative weights, including
        // zero. No template emits a +0 signal in v1, but the renderer
        // contract is "non-veto → signed weight", so +0 is the
        // self-consistent rendering.
        let signal = Signal(kind: .testBodyPattern, weight: 0, detail: "Edge")
        #expect(signal.formattedLine == "Edge (+0)")
    }

    @Test
    func negativeWeightRendersWithMinusPrefix() {
        // Swift integer rendering already prefixes negatives with `-`,
        // so the formatter prefixes nothing extra — the resulting line
        // shows a single `-`.
        let signal = Signal(kind: .antiCommutativityNaming, weight: -30, detail: "Anti-commutativity verb")
        #expect(signal.formattedLine == "Anti-commutativity verb (-30)")
    }

    @Test
    func vetoSignalRendersVetoLabelInsteadOfWeight() {
        // Veto weight is `Int.min`, a sentinel — the formatted line
        // shows `(veto)` instead of the numerical weight to avoid
        // exposing the implementation detail in user-facing text.
        let signal = Signal(
            kind: .nonDeterministicBody,
            weight: Signal.vetoWeight,
            detail: "Non-deterministic API in body: Date()"
        )
        #expect(signal.formattedLine == "Non-deterministic API in body: Date() (veto)")
    }

    @Test
    func crossValidationPlus20Match() {
        // Pinned shape used by `applyCrossValidation` in
        // SwiftInferTemplates — the M3.5 cross-validation seam relies
        // on this rendering remaining stable across the M4.4 refactor.
        let signal = Signal(
            kind: .crossValidation,
            weight: 20,
            detail: "Cross-validated by TestLifter"
        )
        #expect(signal.formattedLine == "Cross-validated by TestLifter (+20)")
    }
}
