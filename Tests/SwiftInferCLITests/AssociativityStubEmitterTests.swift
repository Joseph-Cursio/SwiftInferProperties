import Foundation
import Testing

@testable import SwiftInferCLI

// V1.46.A — AssociativityStubEmitter unit tests.
//
// Mirrors CommutativityStubEmitterTests: pins load-bearing pieces of
// the emitted source (imports, three-arg nested call shape, equality
// form per carrier, seed hex, trial budget, VERIFY_* markers + new
// VERIFY_EDGE_SLOT marker, per-slot rotation logic, edge generator
// references, carrier-specific dispatch) without golden-file matching.
// Subprocess-based end-to-end coverage lands in V1.46.D.4.

@Suite("AssociativityStubEmitter — V1.46.A stub emission")
struct AssociativityStubEmitterTests {

    private static let canonicalSeed = AssociativityStubEmitter.SeedHex(
        stateA: 0xDEAD_BEEF_CAFE_BABE,
        stateB: 0x0123_4567_89AB_CDEF,
        stateC: 0xFEDC_BA98_7654_3210,
        stateD: 0xAAAA_BBBB_CCCC_DDDD
    )

    private static func inputs(
        functionCall: String = "Complex.add",
        extraImports: [String] = [],
        carrierType: String = "Complex<Double>",
        trialBudget: AssociativityStubEmitter.TrialBudget = .small
    ) -> AssociativityStubEmitter.Inputs {
        AssociativityStubEmitter.Inputs(
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
        let source = try AssociativityStubEmitter.emit(Self.inputs())
        #expect(!source.isEmpty)
    }

    @Test("non-supported carrier raises .unsupportedCarrier")
    func unsupportedCarrierThrows() throws {
        do {
            _ = try AssociativityStubEmitter.emit(Self.inputs(carrierType: "Array<Int>"))
            Issue.record("expected .unsupportedCarrier; emit succeeded")
        } catch let error as VerifyError {
            switch error {
            case let .unsupportedCarrier(carrier, expected):
                #expect(carrier == "Array<Int>")
                #expect(expected == AssociativityStubEmitter.supportedCarriers)

            default:
                Issue.record("expected .unsupportedCarrier; got \(error)")
            }
        }
    }

    @Test("supportedCarriers contains all three V1.46.A carriers")
    func supportedCarriersListIsLoadBearing() {
        #expect(AssociativityStubEmitter.supportedCarriers.contains("Complex<Double>"))
        #expect(AssociativityStubEmitter.supportedCarriers.contains("Double"))
        #expect(AssociativityStubEmitter.supportedCarriers.contains("Int"))
    }

    // MARK: - Imports (Complex<Double>)

    @Test("Complex<Double> stub imports the kit chain")
    func stubContainsMandatoryImports() throws {
        let source = try AssociativityStubEmitter.emit(Self.inputs())
        #expect(source.contains("import ComplexModule"))
        #expect(source.contains("import RealModule"))
        #expect(source.contains("import PropertyBased"))
        #expect(source.contains("import PropertyLawComplex"))
        #expect(source.contains("import Foundation"))
    }

    @Test("stub appends caller-supplied extra imports without duplication")
    func stubMergesExtraImports() throws {
        let source = try AssociativityStubEmitter.emit(
            Self.inputs(extraImports: ["MyTarget", "ComplexModule", "  ", ""])
        )
        let occurrences = source.components(separatedBy: "import ComplexModule").count - 1
        #expect(occurrences == 1)
        #expect(source.contains("import MyTarget"))
    }

    // MARK: - Three-arg nested call shape

    @Test("stub renders f(f(a, b), c) (left-associated) and f(a, f(b, c)) (right-associated)")
    func threeArgNestedCallShape() throws {
        let source = try AssociativityStubEmitter.emit(
            Self.inputs(functionCall: "Complex.add")
        )
        #expect(source.contains("Complex.add(Complex.add(valueA, valueB), valueC)"))
        #expect(source.contains("Complex.add(valueA, Complex.add(valueB, valueC))"))
    }

    @Test("equality compares lhsResult (left-assoc) vs rhsResult (right-assoc)")
    func equalityIsApproximateOnAssociationResults() throws {
        let source = try AssociativityStubEmitter.emit(Self.inputs())
        // The associativity property is f(f(a,b),c) ≈ f(a,f(b,c)). The
        // assertion compares the two association orders, not the
        // results against the inputs.
        #expect(source.contains("lhsResult.isApproximatelyEqual(to: rhsResult)"))
    }

    // MARK: - Seed hex formatting

    @Test("seed components render as uppercase hex")
    func seedRendersAsUppercaseHex() throws {
        let source = try AssociativityStubEmitter.emit(Self.inputs())
        #expect(source.contains("0xDEADBEEFCAFEBABE"))
        #expect(source.contains("0x123456789ABCDEF"))
        #expect(source.contains("0xFEDCBA9876543210"))
        #expect(source.contains("0xAAAABBBBCCCCDDDD"))
    }

    // MARK: - Trial budget

    @Test("small budget renders trials = 100")
    func smallBudgetRendersAsHundred() throws {
        let source = try AssociativityStubEmitter.emit(Self.inputs(trialBudget: .small))
        #expect(source.contains("let trials = 100"))
    }

    @Test("standard budget renders trials = 1000")
    func standardBudgetRendersAsThousand() throws {
        let source = try AssociativityStubEmitter.emit(Self.inputs(trialBudget: .standard))
        #expect(source.contains("let trials = 1000"))
    }

    // MARK: - V1.43 marker contract + V1.46 VERIFY_EDGE_SLOT

    @Test("Complex<Double> stub emits the per-pass VERIFY_* markers (incl. VERIFY_EDGE_SLOT)")
    func stubEmitsVerifyMarkers() throws {
        let source = try AssociativityStubEmitter.emit(Self.inputs())
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
        // V1.46.A new advisory marker — slot index of edge value on FAIL.
        #expect(source.contains("VERIFY_EDGE_SLOT:"))
    }

    @Test("Complex<Double> stub references edgeCaseBiased() + complexEdgeCases")
    func stubReferencesEdgeCaseBiased() throws {
        let source = try AssociativityStubEmitter.emit(Self.inputs())
        #expect(source.contains("Gen<Complex<Double>>.edgeCaseBiased()"))
        #expect(source.contains("Gen<Complex<Double>>.complexEdgeCases"))
    }

    @Test("Complex<Double> stub edge match uses rawStorage")
    func stubMatchesEdgeIndexViaRawStorage() throws {
        let source = try AssociativityStubEmitter.emit(Self.inputs())
        #expect(source.contains("value.rawStorage"))
        #expect(!source.contains("entry.real.isNaN"))
    }

    @Test("Complex<Double> edge pass per-slot rotation places edge into slot (trial % 3)")
    func complexEdgePassRotatesSlot() throws {
        let source = try AssociativityStubEmitter.emit(Self.inputs())
        // Edge pass declares the edge generator; the non-edge slots
        // reuse Pass 1's top-level `defaultGenerator`. Per-slot
        // rotation: trial t puts edge into slot (t % 3).
        #expect(source.contains("let edgeGenerator: Generator<Complex<Double>"))
        #expect(source.contains("let edgeSlot = trial % 3"))
        #expect(source.contains("let edgeValue = edgeGenerator.run(using: &rng)"))
        // All three slot-rotation branches present.
        #expect(source.contains("valueA = edgeValue"))
        #expect(source.contains("valueB = edgeValue"))
        #expect(source.contains("valueC = edgeValue"))
        // matchEdgeCaseIndex runs against edge value, not a fixed slot.
        #expect(source.contains("matchEdgeCaseIndex(edgeValue)"))
        // The Pass 1 `defaultGenerator` is the single top-level
        // declaration — no duplicate in Pass 2.
        let occurrences = source.components(
            separatedBy: "let defaultGenerator: Generator<Complex<Double>"
        ).count - 1
        #expect(occurrences == 1)
    }

    @Test("stub exits 1 on FAIL and 0 on PASS")
    func stubExitsWithCorrectCodes() throws {
        let source = try AssociativityStubEmitter.emit(Self.inputs())
        #expect(source.contains("exit(1)"))
        #expect(source.contains("exit(0)"))
    }

    @Test("same-seed reproducibility — two emit calls produce byte-identical source")
    func sameSeedReproducible() throws {
        let first = try AssociativityStubEmitter.emit(Self.inputs())
        let second = try AssociativityStubEmitter.emit(Self.inputs())
        #expect(first == second)
    }

    // MARK: - V1.46.A Double carrier

    @Test("Double carrier emits two-pass stub (no ComplexModule / PropertyLawComplex imports)")
    func doubleCarrierEmits() throws {
        let source = try AssociativityStubEmitter.emit(
            Self.inputs(functionCall: "{ (a: Double, b: Double) in a + b }", carrierType: "Double")
        )
        #expect(!source.isEmpty)
        #expect(!source.contains("import ComplexModule"))
        #expect(!source.contains("import PropertyLawComplex"))
        #expect(source.contains("import RealModule"))
        #expect(source.contains("import PropertyBased"))
    }

    @Test("Double associativity uses the NaN-reflexive oracle (sameResult)")
    func doubleNaNReflexiveOracle() throws {
        let source = try AssociativityStubEmitter.emit(
            Self.inputs(functionCall: "{ (a: Double, b: Double) in a + b }", carrierType: "Double")
        )
        #expect(source.contains("func sameResult(_ lhs: Double, _ rhs: Double) -> Bool"))
        #expect(source.contains("!sameResult(lhsResult, rhsResult)"))
        #expect(source.contains("lhsResult.isApproximatelyEqual(to: rhsResult)") == false)
    }

    @Test("Double carrier uses the real-axis edge set for edge pass + per-slot rotation")
    func doubleCarrierEdgePassUsesRealAxisEdgeSet() throws {
        let source = try AssociativityStubEmitter.emit(
            Self.inputs(functionCall: "{ (a: Double, b: Double) in a + b }", carrierType: "Double")
        )
        #expect(source.contains("Gen<Int>.int(in: 0 ..< 90)"))
        #expect(source.contains("return Double.nan"))
        #expect(source.contains("if value.isNaN { return 0 }"))
        #expect(!source.contains("value.isNaN ? 0 : -1"))
        // Per-slot rotation applies on the Double edge pass too.
        #expect(source.contains("let edgeSlot = trial % 3"))
        #expect(source.contains("VERIFY_EDGE_SLOT:"))
    }

    // MARK: - V1.46.A Int carrier

    @Test("Int carrier emits single-pass stub with strict `!=` check")
    func intCarrierEmits() throws {
        let source = try AssociativityStubEmitter.emit(
            Self.inputs(functionCall: "{ (a: Int, b: Int) in a + b }", carrierType: "Int")
        )
        #expect(!source.isEmpty)
        #expect(!source.contains("isApproximatelyEqual"))
        // Strict inequality — `lhsResult != rhsResult` triggers the FAIL.
        #expect(source.contains("lhsResult != rhsResult"))
        // Nested three-arg shape with the inlined closure call.
        #expect(source.contains(
            "{ (a: Int, b: Int) in a + b }({ (a: Int, b: Int) in a + b }(valueA, valueB), valueC)"
        ))
    }

    @Test("Int carrier emits zero-edge sentinel (parser produces .bothPass)")
    func intCarrierEmitsEdgeSentinel() throws {
        let source = try AssociativityStubEmitter.emit(
            Self.inputs(functionCall: "{ (a: Int, b: Int) in a + b }", carrierType: "Int")
        )
        #expect(source.contains("VERIFY_EDGE_RESULT: PASS"))
        #expect(source.contains("VERIFY_EDGE_TRIALS: 0"))
        #expect(source.contains("VERIFY_EDGE_SAMPLED: 0"))
        #expect(!source.contains("VERIFY_EDGE_TRIAL:"))
        #expect(!source.contains("VERIFY_EDGE_INDEX:"))
        // No edge pass — no VERIFY_EDGE_SLOT marker on Int either.
        #expect(!source.contains("VERIFY_EDGE_SLOT:"))
    }

    // MARK: - V1.141 shrink phase (triple)

    @Test("Complex<Double> default pass shrinks all three triple components on failure")
    func complexCarrierEmitsTripleShrinkPhase() throws {
        let source = try AssociativityStubEmitter.emit(Self.inputs())
        #expect(source.contains("VERIFY_DEFAULT_SHRUNK:"))
        #expect(source.contains("VERIFY_SHRINK_STEPS:"))
        #expect(source.contains("func associativityFails"))
        #expect(source.contains("shrunkA.real.shrink(towards: 0)"))
        #expect(source.contains("shrunkC.imaginary.shrink(towards: 0)"))
    }

    @Test("Double / Int default passes shrink all three triple components toward 0")
    func scalarCarriersEmitTripleShrinkPhase() throws {
        let doubleSource = try AssociativityStubEmitter.emit(
            Self.inputs(functionCall: "{ (a: Double, b: Double) in a + b }", carrierType: "Double")
        )
        #expect(doubleSource.contains("VERIFY_DEFAULT_SHRUNK:"))
        #expect(doubleSource.contains("shrunkA.shrink(towards: 0)"))
        #expect(doubleSource.contains("shrunkC.shrink(towards: 0)"))

        let intSource = try AssociativityStubEmitter.emit(
            Self.inputs(functionCall: "{ (a: Int, b: Int) in a + b }", carrierType: "Int")
        )
        #expect(intSource.contains("VERIFY_DEFAULT_SHRUNK:"))
        #expect(intSource.contains("shrunkB.shrink(towards: 0)"))
    }
}
