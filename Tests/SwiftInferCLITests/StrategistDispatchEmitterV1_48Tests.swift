import Foundation
import Testing

@testable import SwiftInferCLI

// V1.48.E — unit tests for the three new template composers added
// in V1.48.A (idempotence-lifted, dual-style-consistency,
// monotonicity). Pins the load-bearing emit shape per template.

@Suite("StrategistDispatchEmitter — V1.48.A new template composers")
struct StrategistDispatchEmitterV148Tests {

    private static let canonicalSeed = StrategistDispatchEmitter.SeedHex(
        stateA: 0x01, stateB: 0x02, stateC: 0x03, stateD: 0x04
    )

    private static func inputs(
        template: String,
        carrier: String = "Int",
        functionCalls: [String] = ["{ (x: Int) in x }"]
    ) -> StrategistDispatchEmitter.Inputs {
        StrategistDispatchEmitter.Inputs(
            carrier: carrier,
            typeShape: nil,
            template: template,
            functionCalls: functionCalls,
            extraImports: [],
            seedHex: canonicalSeed,
            trialBudget: .small
        )
    }

    // MARK: - Idempotence-lifted (V1.48.A.1)

    @Test("idempotence-lifted emits Gen<[T]> via kit's .array(of:) helper")
    func idempotenceLiftedUsesKitArrayHelper() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "idempotence-lifted",
                functionCalls: ["{ (xs: [Int]) in xs.sorted() }"]
            )
        )
        #expect(source.contains("let elementGenerator: Generator<Int"))
        #expect(source.contains("elementGenerator.array(of: 0 ... 8)"))
        #expect(source.contains("let defaultGenerator: Generator<[Int]"))
    }

    @Test("idempotence-lifted emits f(f(xs)) idempotence check")
    func idempotenceLiftedEmitsIdempotenceCheck() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "idempotence-lifted",
                functionCalls: ["{ (xs: [Int]) in xs.sorted() }"]
            )
        )
        #expect(source.contains("let onceResult = { (xs: [Int]) in xs.sorted() }(xs)"))
        #expect(source.contains("let twiceResult = { (xs: [Int]) in xs.sorted() }(onceResult)"))
        #expect(source.contains("onceResult != twiceResult"))
    }

    @Test("idempotence-lifted single-pass + zero-edge sentinel")
    func idempotenceLiftedZeroEdgeSentinel() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(template: "idempotence-lifted")
        )
        #expect(source.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(source.contains("VERIFY_EDGE_RESULT: PASS"))
        #expect(source.contains("VERIFY_EDGE_TRIALS: 0"))
    }

    // MARK: - Dual-style-consistency (V1.48.A.2)

    @Test("dual-style-consistency emits non-mutating call + var-copy mutation idiom")
    func dualStyleConsistencyMutationIdiom() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "dual-style-consistency",
                functionCalls: ["{ (x: Int) in x }", "advance"]
            )
        )
        #expect(source.contains("let nonMutResult = { (x: Int) in x }(original)"))
        #expect(source.contains("var mutCopy = original"))
        #expect(source.contains("mutCopy.advance()"))
        #expect(source.contains("nonMutResult != mutCopy"))
    }

    @Test("dual-style-consistency renders a qualified non-mutating member as an instance call")
    func dualStyleConsistencyInstanceMemberCallShape() throws {
        // A resolver-qualified member (`Type.method`) must be invoked as
        // `original.method()` — `Type.method(original)` is the curried
        // unbound form, not a value. A bare (dot-free) name stays
        // `name(original)` (the closure / free-function preamble shape).
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "dual-style-consistency",
                functionCalls: ["Toggle.reversed", "reverse"]
            )
        )
        #expect(source.contains("let nonMutResult = original.reversed()"))
        #expect(!source.contains("Toggle.reversed(original)"))
        #expect(source.contains("mutCopy.reverse()"))
    }

    @Test("dual-style-consistency throws if functionCalls.count != 2")
    func dualStyleConsistencyRequiresPair() throws {
        #expect(throws: VerifyError.self) {
            _ = try StrategistDispatchEmitter.emit(
                Self.inputs(
                    template: "dual-style-consistency",
                    functionCalls: ["only-one"]
                )
            )
        }
    }

    @Test("dual-style-consistency emits the standard markers + single-pass")
    func dualStyleConsistencyMarkers() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "dual-style-consistency",
                functionCalls: ["{ (x: Int) in x }", "noop"]
            )
        )
        #expect(source.contains("VERIFY_DEFAULT_RESULT: FAIL"))
        #expect(source.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(source.contains("VERIFY_EDGE_RESULT: PASS"))
        #expect(source.contains("VERIFY_EDGE_TRIALS: 0"))
    }

    // MARK: - Monotonicity (V1.48.A.3)

    @Test("monotonicity draws 2 values, sorts via min/max, asserts f(a) ≤ f(b)")
    func monotonicityComparison() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "monotonicity",
                functionCalls: ["{ (x: Int) in x * 2 }"]
            )
        )
        #expect(source.contains("let firstDraw = defaultGenerator.run"))
        #expect(source.contains("let secondDraw = defaultGenerator.run"))
        #expect(source.contains("let valueA = min(firstDraw, secondDraw)"))
        #expect(source.contains("let valueB = max(firstDraw, secondDraw)"))
        #expect(source.contains("{ (x: Int) in x * 2 }(valueA)"))
        #expect(source.contains("{ (x: Int) in x * 2 }(valueB)"))
        // monotonicity violation == "resultA > resultB"
        #expect(source.contains("resultA > resultB"))
    }

    @Test("monotonicity emits the standard markers + single-pass")
    func monotonicityMarkers() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(template: "monotonicity")
        )
        #expect(source.contains("VERIFY_DEFAULT_RESULT: FAIL"))
        #expect(source.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(source.contains("VERIFY_EDGE_RESULT: PASS"))
        #expect(source.contains("VERIFY_EDGE_TRIALS: 0"))
    }

    // MARK: - Dispatch coverage

    @Test("all three new templates dispatch through the strategist (Int carrier)")
    func newTemplatesDispatchInt() throws {
        for template in ["idempotence-lifted", "dual-style-consistency", "monotonicity"] {
            let functionCalls: [String]
            switch template {
            case "dual-style-consistency":
                functionCalls = ["{ (x: Int) in x }", "noop"]

            default:
                functionCalls = ["{ (x: Int) in x }"]
            }
            let source = try StrategistDispatchEmitter.emit(
                Self.inputs(template: template, functionCalls: functionCalls)
            )
            #expect(!source.isEmpty, "template \(template) produced empty source")
        }
    }
}
