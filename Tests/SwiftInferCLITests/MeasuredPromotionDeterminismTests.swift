import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Cycle 118 — the A1 measured-promotion sign-off rests on one property:
/// the measured survey has **zero cycle-to-cycle variance**, so a single
/// confirmed run is equivalent to the three-cycle calibration discipline
/// (which exists to absorb the variance of human triage / corpus
/// selection). This suite locks the root of that determinism — the
/// verifier seed — at the unit level; the end-to-end reproducibility proof
/// (verify the same identity twice → identical Result) is the
/// `.subprocess` `PromotionDeterminismMeasuredTests`.
@Suite("Measured-promotion determinism — seed reproducibility (cycle 118)")
struct MeasuredPromotionDeterminismTests {

    @Test("seedTuple is deterministic for a given reducer (same qualifiedName → identical seed)")
    func seedIsDeterministic() {
        let counter = candidate(functionName: "reduce", enclosingTypeName: "CounterReducer")
        let first = ActionSequenceStubEmitter.seedTuple(for: counter)
        let second = ActionSequenceStubEmitter.seedTuple(for: counter)
        #expect(first == second)
        // A well-formed Xoshiro256** seed: four `0x`-prefixed hex words.
        #expect(first.split(separator: ",").count == 4)
    }

    @Test("seedTuple varies by reducer identity (different qualifiedName → different seed)")
    func seedVariesByReducer() {
        let counter = candidate(functionName: "reduce", enclosingTypeName: "CounterReducer")
        let settings = candidate(functionName: "reduce", enclosingTypeName: "SettingsReducer")
        let freeFn = candidate(functionName: "reduce")  // qualifiedName "reduce"
        #expect(ActionSequenceStubEmitter.seedTuple(for: counter)
            != ActionSequenceStubEmitter.seedTuple(for: settings))
        #expect(ActionSequenceStubEmitter.seedTuple(for: counter)
            != ActionSequenceStubEmitter.seedTuple(for: freeFn))
    }

    private func candidate(
        functionName: String,
        enclosingTypeName: String? = nil
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/X/F.swift:1",
            enclosingTypeName: enclosingTypeName,
            functionName: functionName,
            signatureShape: .stateActionReturnsState,
            stateTypeName: "State",
            actionTypeName: "Action",
            carrierKind: enclosingTypeName == nil ? .elmStyle : .generic
        )
    }
}
