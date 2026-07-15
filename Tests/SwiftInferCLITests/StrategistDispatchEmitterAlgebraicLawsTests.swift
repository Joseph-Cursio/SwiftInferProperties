import Foundation
import Testing

@testable import SwiftInferCLI

/// Fast emit-guards for the three algebraic-law composers wired for measured
/// verify (involution / binary-idempotence / homomorphism). These assert the
/// emitted stub carries the correct law oracle without spawning a build — the
/// end-to-end build+run proof lives in `AlgebraicLawsVerifyMeasuredTests`.
@Suite("StrategistDispatchEmitter — algebraic-law composers")
struct StrategistAlgebraicLawEmitTests {

    private func emit(template: String, carrier: String, calls: [String]) throws -> String {
        try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: carrier,
                typeShape: nil,
                template: template,
                functionCalls: calls,
                extraImports: [],
                seedHex: RoundTripStubEmitter.SeedHex(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
                trialBudget: .small
            )
        )
    }

    @Test("involution emits f(f(x)) == x")
    func involutionOracle() throws {
        let source = try emit(template: "involution", carrier: "Int", calls: ["Laws.negated"])
        #expect(source.contains("let onceResult = Laws.negated(value)"))
        #expect(source.contains("let twiceResult = Laws.negated(onceResult)"))
        // The RHS is the ORIGINAL input, not `f(x)` — that is what makes it an
        // involution and not idempotence.
        #expect(source.contains("if twiceResult != value"))
    }

    @Test("binary-idempotence emits op(x, x) == x")
    func binaryIdempotenceOracle() throws {
        let source = try emit(template: "binary-idempotence", carrier: "Int", calls: ["Laws.maximum"])
        #expect(source.contains("let result = Laws.maximum(value, value)"))
        #expect(source.contains("if result != value"))
    }

    @Test("homomorphism emits h(a + b) == h(a) + h(b) over generated arrays")
    func homomorphismOracle() throws {
        // The dispatch strips `[Int]` → `Int`; the composer wraps the element
        // generator in `.array(of:)` and checks additivity over concatenation.
        let source = try emit(template: "homomorphism", carrier: "Int", calls: ["Laws.tally"])
        #expect(source.contains(".array(of: 0 ... 8)"))
        #expect(source.contains("let combined = Laws.tally(aValue + bValue)"))
        #expect(source.contains("let summed = Laws.tally(aValue) + Laws.tally(bValue)"))
        #expect(source.contains("if combined != summed"))
    }
}
