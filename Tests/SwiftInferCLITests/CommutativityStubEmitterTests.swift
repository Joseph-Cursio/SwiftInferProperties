import Foundation
import Testing

@testable import SwiftInferCLI

// V1.45.A — CommutativityStubEmitter unit tests.
//
// Mirrors IdempotenceStubEmitterTests: pins load-bearing pieces of the
// emitted source (imports, two-arg call shape, equality form per
// carrier, seed hex, trial budget, VERIFY_* markers, edge generator
// references, carrier-specific dispatch) without golden-file matching.
// Subprocess-based end-to-end coverage lands in V1.45.E.3.

@Suite("CommutativityStubEmitter — V1.45.A stub emission")
struct CommutativityStubEmitterTests {

    private static let canonicalSeed = CommutativityStubEmitter.SeedHex(
        stateA: 0xDEAD_BEEF_CAFE_BABE,
        stateB: 0x0123_4567_89AB_CDEF,
        stateC: 0xFEDC_BA98_7654_3210,
        stateD: 0xAAAA_BBBB_CCCC_DDDD
    )

    private static func inputs(
        functionCall: String = "Complex.add",
        extraImports: [String] = [],
        carrierType: String = "Complex<Double>",
        trialBudget: CommutativityStubEmitter.TrialBudget = .small
    ) -> CommutativityStubEmitter.Inputs {
        CommutativityStubEmitter.Inputs(
            functionCall: functionCall,
            extraImports: extraImports,
            carrierType: carrierType,
            seedHex: canonicalSeed,
            trialBudget: trialBudget
        )
    }

    // MARK: - Carrier validation

    @Test("Complex<Double> carrier compiles to a stub")
    func complexDoubleCarrierEmits() throws {
        let source = try CommutativityStubEmitter.emit(Self.inputs())
        #expect(!source.isEmpty)
    }

    @Test("non-supported carrier raises .unsupportedCarrier")
    func unsupportedCarrierThrows() throws {
        do {
            _ = try CommutativityStubEmitter.emit(Self.inputs(carrierType: "Array<Int>"))
            Issue.record("expected .unsupportedCarrier; emit succeeded")
        } catch let error as VerifyError {
            switch error {
            case let .unsupportedCarrier(carrier, expected):
                #expect(carrier == "Array<Int>")
                #expect(expected == CommutativityStubEmitter.supportedCarriers)

            default:
                Issue.record("expected .unsupportedCarrier; got \(error)")
            }
        }
    }

    @Test("supportedCarriers contains all three V1.45.A carriers")
    func supportedCarriersListIsLoadBearing() {
        #expect(CommutativityStubEmitter.supportedCarriers.contains("Complex<Double>"))
        #expect(CommutativityStubEmitter.supportedCarriers.contains("Double"))
        #expect(CommutativityStubEmitter.supportedCarriers.contains("Int"))
    }

    // MARK: - Imports (Complex<Double>)

    @Test("Complex<Double> stub imports the kit chain")
    func stubContainsMandatoryImports() throws {
        let source = try CommutativityStubEmitter.emit(Self.inputs())
        #expect(source.contains("import ComplexModule"))
        #expect(source.contains("import RealModule"))
        #expect(source.contains("import PropertyBased"))
        #expect(source.contains("import PropertyLawComplex"))
        #expect(source.contains("import Foundation"))
    }

    @Test("stub appends caller-supplied extra imports without duplication")
    func stubMergesExtraImports() throws {
        let source = try CommutativityStubEmitter.emit(
            Self.inputs(extraImports: ["MyTarget", "ComplexModule", "  ", ""])
        )
        let occurrences = source.components(separatedBy: "import ComplexModule").count - 1
        #expect(occurrences == 1)
        #expect(source.contains("import MyTarget"))
    }

    // MARK: - Two-arg call shape

    @Test("stub renders f(lhs, rhs) and f(rhs, lhs) (commutativity swap)")
    func twoArgSwapCallShape() throws {
        let source = try CommutativityStubEmitter.emit(
            Self.inputs(functionCall: "Complex.add")
        )
        #expect(source.contains("Complex.add(lhs, rhs)"))
        #expect(source.contains("Complex.add(rhs, lhs)"))
    }

    @Test("equality compares lhsResult vs rhsResult (not vs inputs)")
    func equalityIsApproximateOnPairResults() throws {
        let source = try CommutativityStubEmitter.emit(Self.inputs())
        // The commutativity property is f(a,b) ≈ f(b,a). The assertion
        // compares the two swapped-order results, NOT the lhs against
        // the original value.
        #expect(source.contains("lhsResult.isApproximatelyEqual(to: rhsResult)"))
    }

    // MARK: - Seed hex formatting

    @Test("seed components render as uppercase hex")
    func seedRendersAsUppercaseHex() throws {
        let source = try CommutativityStubEmitter.emit(Self.inputs())
        #expect(source.contains("0xDEADBEEFCAFEBABE"))
        #expect(source.contains("0x123456789ABCDEF"))
        #expect(source.contains("0xFEDCBA9876543210"))
        #expect(source.contains("0xAAAABBBBCCCCDDDD"))
    }

    // MARK: - Trial budget

    @Test("small budget renders trials = 100")
    func smallBudgetRendersAsHundred() throws {
        let source = try CommutativityStubEmitter.emit(Self.inputs(trialBudget: .small))
        #expect(source.contains("let trials = 100"))
    }

    @Test("standard budget renders trials = 1000")
    func standardBudgetRendersAsThousand() throws {
        let source = try CommutativityStubEmitter.emit(Self.inputs(trialBudget: .standard))
        #expect(source.contains("let trials = 1000"))
    }

    // MARK: - V1.43 marker contract

    @Test("Complex<Double> stub emits the per-pass VERIFY_* markers")
    func stubEmitsVerifyMarkers() throws {
        let source = try CommutativityStubEmitter.emit(Self.inputs())
        #expect(source.contains("VERIFY_DEFAULT_RESULT: FAIL"))
        #expect(source.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(source.contains("VERIFY_DEFAULT_TRIAL:"))
        #expect(source.contains("VERIFY_DEFAULT_INPUT:"))
        #expect(source.contains("VERIFY_DEFAULT_FORWARD:"))
        #expect(source.contains("VERIFY_DEFAULT_INVERSE:"))
        #expect(source.contains("VERIFY_DEFAULT_TRIALS:"))
        #expect(source.contains("VERIFY_EDGE_RESULT: FAIL"))
        #expect(source.contains("VERIFY_EDGE_RESULT: PASS"))
        #expect(source.contains("VERIFY_EDGE_INDEX:"))
        #expect(source.contains("VERIFY_EDGE_SAMPLED:"))
    }

    @Test("Complex<Double> stub references edgeCaseBiased() + complexEdgeCases")
    func stubReferencesEdgeCaseBiased() throws {
        let source = try CommutativityStubEmitter.emit(Self.inputs())
        #expect(source.contains("Gen<Complex<Double>>.edgeCaseBiased()"))
        #expect(source.contains("Gen<Complex<Double>>.complexEdgeCases"))
    }

    @Test("Complex<Double> stub edge match uses rawStorage")
    func stubMatchesEdgeIndexViaRawStorage() throws {
        let source = try CommutativityStubEmitter.emit(Self.inputs())
        #expect(source.contains("value.rawStorage"))
        #expect(!source.contains("entry.real.isNaN"))
    }

    @Test("Complex<Double> edge pass biases lhs to edge generator + rhs to default")
    func complexEdgePassBiasesFirstValue() throws {
        let source = try CommutativityStubEmitter.emit(Self.inputs())
        // Edge pass declares the edge generator; the rhs reuses Pass
        // 1's top-level `defaultGenerator` (declaring a second
        // top-level `let defaultGenerator` would clash). lhs draws
        // from edge, rhs from default — surfaces "edge × finite"
        // pairings (~10/100).
        #expect(source.contains("let edgeGenerator: Generator<Complex<Double>"))
        #expect(source.contains("let lhs = edgeGenerator.run(using: &rng)"))
        #expect(source.contains("let rhs = defaultGenerator.run(using: &rng)"))
        // The Pass 1 `defaultGenerator` is the single top-level
        // declaration — no duplicate in Pass 2.
        let occurrences = source.components(
            separatedBy: "let defaultGenerator: Generator<Complex<Double>"
        ).count - 1
        #expect(occurrences == 1)
    }

    @Test("stub exits 1 on FAIL and 0 on PASS")
    func stubExitsWithCorrectCodes() throws {
        let source = try CommutativityStubEmitter.emit(Self.inputs())
        #expect(source.contains("exit(1)"))
        #expect(source.contains("exit(0)"))
    }

    // MARK: - V1.45.A Double carrier

    @Test("Double carrier emits two-pass stub (no ComplexModule / PropertyLawComplex imports)")
    func doubleCarrierEmits() throws {
        let source = try CommutativityStubEmitter.emit(
            Self.inputs(functionCall: "{ (a: Double, b: Double) in a + b }", carrierType: "Double")
        )
        #expect(!source.isEmpty)
        #expect(!source.contains("import ComplexModule"))
        #expect(!source.contains("import PropertyLawComplex"))
        #expect(source.contains("import RealModule"))
        #expect(source.contains("import PropertyBased"))
    }

    @Test("Double carrier uses inlined doubleWithNaN for edge pass")
    func doubleCarrierEdgePassUsesDoubleWithNaN() throws {
        let source = try CommutativityStubEmitter.emit(
            Self.inputs(functionCall: "{ (a: Double, b: Double) in a + b }", carrierType: "Double")
        )
        #expect(source.contains("Gen<Int>.int(in: 0 ..< 20)"))
        #expect(source.contains("return Double.nan"))
        #expect(source.contains("value.isNaN ? 0 : -1"))
    }

    // MARK: - V1.45.A Int carrier

    @Test("Int carrier emits single-pass stub with strict `!=` check")
    func intCarrierEmits() throws {
        let source = try CommutativityStubEmitter.emit(
            Self.inputs(functionCall: "{ (a: Int, b: Int) in a + b }", carrierType: "Int")
        )
        #expect(!source.isEmpty)
        #expect(!source.contains("isApproximatelyEqual"))
        // Strict inequality — `lhsResult != rhsResult` triggers the FAIL.
        #expect(source.contains("lhsResult != rhsResult"))
    }

    @Test("Int carrier emits zero-edge sentinel (parser produces .bothPass)")
    func intCarrierEmitsEdgeSentinel() throws {
        let source = try CommutativityStubEmitter.emit(
            Self.inputs(functionCall: "{ (a: Int, b: Int) in a + b }", carrierType: "Int")
        )
        #expect(source.contains("VERIFY_EDGE_RESULT: PASS"))
        #expect(source.contains("VERIFY_EDGE_TRIALS: 0"))
        #expect(source.contains("VERIFY_EDGE_SAMPLED: 0"))
        #expect(!source.contains("VERIFY_EDGE_TRIAL:"))
        #expect(!source.contains("VERIFY_EDGE_INDEX:"))
    }
}
