import Foundation
import PropertyLawCore
import Testing

@testable import SwiftInferCLI
@testable import SwiftInferCore

@Suite("StrategistDispatchEmitter — V1.47.E template × emit dispatch")
struct StrategistDispatchEmitterEmitTests {

    private static let canonicalSeed = StrategistDispatchEmitter.SeedHex(
        stateA: 0x01, stateB: 0x02, stateC: 0x03, stateD: 0x04
    )

    private static func inputs(
        template: String,
        carrier: String = "Int",
        functionCalls: [String] = ["{ (x: Int) in x }"],
        trialBudget: StrategistDispatchEmitter.TrialBudget = .small,
        isInstanceMethod: Bool = false,
        isMutatingMethod: Bool = false,
        isNullary: Bool = false,
        returnsSelfType: Bool = false
    ) -> StrategistDispatchEmitter.Inputs {
        StrategistDispatchEmitter.Inputs(
            carrier: carrier,
            typeShape: nil,
            template: template,
            functionCalls: functionCalls,
            seedHex: canonicalSeed,
            trialBudget: trialBudget,
            extraImports: [],
            isInstanceMethod: isInstanceMethod,
            isMutatingMethod: isMutatingMethod,
            isNullary: isNullary,
            returnsSelfType: returnsSelfType
        )
    }

    @Test("round-trip emits forward+inverse calls + VERIFY markers + boundary Pass 2")
    func roundTripEmitShape() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "round-trip",
                functionCalls: [
                    "{ (x: Int) in x + 1 }",
                    "{ (x: Int) in x - 1 }",
                ]
            )
        )
        #expect(source.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(source.contains("VERIFY_DEFAULT_RESULT: FAIL"))
        #expect(source.contains("Gen<Int>.int()"))
        #expect(source.contains("{ (x: Int) in x + 1 }(value)"))
        #expect(source.contains("{ (x: Int) in x - 1 }(forwardResult)"))
        #expect(source.contains("VERIFY_EDGE_RESULT: PASS"))
        // V1.153 — Pass 2 is a real boundary sweep for an integer carrier, so
        // the zero-trial sentinel is gone. It survives only for carriers with
        // no curated boundary set (see `EdgePassTests`).
        #expect(source.contains("VERIFY_EDGE_RESULT"))
        #expect(!source.contains("VERIFY_EDGE_TRIALS: 0"))
    }

    @Test("idempotence emits f(f(x)) shape")
    func idempotenceEmitShape() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "idempotence",
                functionCalls: ["{ (x: Int) in x * x }"]
            )
        )
        // The function is bound once with an explicit type and called by name.
        // This test used to pin the inline form — `{ … }(value)` — which is the
        // defect itself: an immediately-applied closure literal has nothing to
        // infer `$0` from, and on a large derived generator the compiler gives
        // up and verify reports `build-failed`. See `AppliedClosureLiteralTests`.
        #expect(source.contains("let applyOnce: (Int) -> Int = { (x: Int) in x * x }"))
        #expect(source.contains("let onceResult = applyOnce(value)"))
        #expect(source.contains("let twiceResult = applyOnce(onceResult)"))
        #expect(source.contains("onceResult != twiceResult"))
    }

    @Test("commutativity emits 2-value f(a, b) / f(b, a) shape")
    func commutativityEmitShape() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "commutativity",
                functionCalls: ["{ (a: Int, b: Int) in a + b }"]
            )
        )
        #expect(source.contains("let lhs = defaultGenerator.run"))
        #expect(source.contains("let rhs = defaultGenerator.run"))
        #expect(source.contains("(lhs, rhs)"))
        #expect(source.contains("(rhs, lhs)"))
    }

    @Test("associativity emits 3-value nested-call shape")
    func associativityEmitShape() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "associativity",
                functionCalls: ["{ (a: Int, b: Int) in a + b }"]
            )
        )
        #expect(source.contains("let valueA = defaultGenerator.run"))
        #expect(source.contains("let valueB = defaultGenerator.run"))
        #expect(source.contains("let valueC = defaultGenerator.run"))
        #expect(source.contains("(valueA, valueB), valueC)"))
        #expect(source.contains("(valueA, "))
    }

    @Test("unsupported template throws .unsupportedTemplate")
    func unsupportedTemplateThrows() throws {
        // The supported set has since grown (idempotence-lifted /
        // dual-style-consistency / monotonicity in V1.48.A; involution /
        // binary-idempotence / homomorphism with the catalogue work). Use a
        // template name outside that set to exercise the .unsupportedTemplate path.
        #expect(throws: VerifyError.self) {
            _ = try StrategistDispatchEmitter.emit(
                Self.inputs(template: "not-a-real-template")
            )
        }
    }

    @Test("seed hex renders into the stub")
    func seedHexRenders() throws {
        let source = try StrategistDispatchEmitter.emit(Self.inputs(template: "idempotence"))
        #expect(source.contains("0x1"))
        #expect(source.contains("0x2"))
        #expect(source.contains("0x3"))
        #expect(source.contains("0x4"))
    }

    @Test("trial budget renders into the stub (small = 100)")
    func smallBudgetRenders() throws {
        let source = try StrategistDispatchEmitter.emit(Self.inputs(template: "idempotence"))
        #expect(source.contains("let trials = 100"))
    }

    // V1.60.A — mutating-instance-method emission for OC carriers.

    @Test("V1.60.A: idempotence on OrderedSet<Int> emits mutating-instance shape")
    func idempotenceOrderedSetMutatingShape() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "idempotence",
                carrier: "OrderedSet<Int>",
                functionCalls: ["OrderedSet.sort"]
            )
        )
        // The new mutating shape produces `var copy = value;
        // copy.sort()` instead of the static `OrderedSet.sort(value)`.
        #expect(source.contains("var onceCopy = value"))
        #expect(source.contains("onceCopy.sort()"))
        #expect(source.contains("var twiceCopy = value"))
        #expect(source.contains("twiceCopy.sort()"))
        // The static-shape call must NOT appear (regression guard).
        #expect(source.contains("OrderedSet.sort(value)") == false)
        #expect(source.contains("OrderedSet.sort(onceResult)") == false)
        // Standard VERIFY markers still emit.
        #expect(source.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(source.contains("VERIFY_DEFAULT_RESULT: FAIL"))
    }

    @Test("V1.60.A: idempotence on non-OC carrier still emits static shape (regression guard)")
    func idempotenceIntCarrierStaticShape() throws {
        // Int isn't in mutatingInstanceCarriers, so the existing
        // static-call emit shape stays.
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(
                template: "idempotence",
                carrier: "Int",
                functionCalls: ["{ (x: Int) in x }"]
            )
        )
        #expect(source.contains("let onceResult"))
        #expect(source.contains("let twiceResult"))
        #expect(source.contains("var onceCopy") == false)
    }

    // Signal-driven instance-method and Cycle 149 dual-style-consistency tests
    // have been moved to DispatchEmitterExtendedTests.swift.
}
