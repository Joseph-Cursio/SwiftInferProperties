import Foundation
import Testing

@testable import SwiftInferCLI

// V1.44.A — IdempotenceStubEmitter unit tests.
//
// Mirrors RoundTripStubEmitterTests: pins load-bearing pieces of the
// emitted source (imports, function-call expressions, seed hex,
// trial-budget literal, VERIFY_* markers, rawStorage-based edge match)
// without golden-file matching. Subprocess-based end-to-end coverage
// lands in V1.44.E.3.

@Suite("IdempotenceStubEmitter — V1.44.A stub emission")
struct IdempotenceStubEmitterTests {

    private static let canonicalSeed = IdempotenceStubEmitter.SeedHex(
        stateA: 0xDEAD_BEEF_CAFE_BABE,
        stateB: 0x0123_4567_89AB_CDEF,
        stateC: 0xFEDC_BA98_7654_3210,
        stateD: 0xAAAA_BBBB_CCCC_DDDD
    )

    private static func inputs(
        functionCall: String = "Complex.exp",
        extraImports: [String] = [],
        carrierType: String = "Complex<Double>",
        trialBudget: IdempotenceStubEmitter.TrialBudget = .small
    ) -> IdempotenceStubEmitter.Inputs {
        IdempotenceStubEmitter.Inputs(
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
        let source = try IdempotenceStubEmitter.emit(Self.inputs())
        #expect(!source.isEmpty)
    }

    @Test("non-Complex<Double> carrier raises .unsupportedCarrier")
    func unsupportedCarrierThrows() throws {
        do {
            _ = try IdempotenceStubEmitter.emit(Self.inputs(carrierType: "Array<Int>"))
            Issue.record("expected .unsupportedCarrier; emit succeeded")
        } catch let error as VerifyError {
            switch error {
            case let .unsupportedCarrier(carrier, expected):
                #expect(carrier == "Array<Int>")
                #expect(expected == IdempotenceStubEmitter.supportedCarriers)

            default:
                Issue.record("expected .unsupportedCarrier; got \(error)")
            }
        }
    }

    @Test("supportedCarriers contains all three V1.44.C carriers")
    func supportedCarriersListIsLoadBearing() {
        #expect(IdempotenceStubEmitter.supportedCarriers.contains("Complex<Double>"))
        #expect(IdempotenceStubEmitter.supportedCarriers.contains("Double"))
        #expect(IdempotenceStubEmitter.supportedCarriers.contains("Int"))
    }

    // MARK: - Imports

    @Test("stub imports the mandatory modules (Complex + PropertyLawComplex chain)")
    func stubContainsMandatoryImports() throws {
        let source = try IdempotenceStubEmitter.emit(Self.inputs())
        #expect(source.contains("import ComplexModule"))
        #expect(source.contains("import RealModule"))
        #expect(source.contains("import PropertyBased"))
        #expect(source.contains("import PropertyLawComplex"))
        #expect(source.contains("import Foundation"))
    }

    @Test("stub appends caller-supplied extra imports without duplication")
    func stubMergesExtraImports() throws {
        let source = try IdempotenceStubEmitter.emit(
            Self.inputs(extraImports: ["MyTarget", "ComplexModule", "  ", ""])
        )
        // ComplexModule was a mandatory import — even when the caller
        // also passes it, the import line appears only once.
        let occurrences = source.components(separatedBy: "import ComplexModule").count - 1
        #expect(occurrences == 1)
        #expect(source.contains("import MyTarget"))
    }

    // MARK: - Function-call shape

    @Test("stub renders f(value) and f(onceResult) (f-twice on input)")
    func twiceAppliedCallShape() throws {
        let source = try IdempotenceStubEmitter.emit(
            Self.inputs(functionCall: "Complex.exp")
        )
        #expect(source.contains("Complex.exp(value)"))
        #expect(source.contains("Complex.exp(onceResult)"))
    }

    // MARK: - Equality assertion

    @Test("equality uses isApproximatelyEqual against onceResult, not value")
    func equalityIsApproximateOnOnceResult() throws {
        let source = try IdempotenceStubEmitter.emit(Self.inputs())
        // The idempotence property is f(f(x)) ≈ f(x). The assertion
        // compares twice-applied vs once-applied, NOT twice-applied
        // vs raw input.
        #expect(source.contains("twiceResult.isApproximatelyEqual(to: onceResult)"))
        #expect(!source.contains("twiceResult.isApproximatelyEqual(to: value)"))
    }

    // MARK: - Seed hex formatting

    @Test("seed components render as uppercase hex")
    func seedRendersAsUppercaseHex() throws {
        let source = try IdempotenceStubEmitter.emit(Self.inputs())
        #expect(source.contains("0xDEADBEEFCAFEBABE"))
        #expect(source.contains("0x123456789ABCDEF"))
        #expect(source.contains("0xFEDCBA9876543210"))
        #expect(source.contains("0xAAAABBBBCCCCDDDD"))
    }

    // MARK: - Trial budget

    @Test("small budget renders trials = 100")
    func smallBudgetRendersAsHundred() throws {
        let source = try IdempotenceStubEmitter.emit(Self.inputs(trialBudget: .small))
        #expect(source.contains("let trials = 100"))
    }

    @Test("standard budget renders trials = 1000")
    func standardBudgetRendersAsThousand() throws {
        let source = try IdempotenceStubEmitter.emit(Self.inputs(trialBudget: .standard))
        #expect(source.contains("let trials = 1000"))
    }

    // MARK: - V1.43 marker contract (reused for parser compatibility)

    @Test("stub emits the per-pass VERIFY_* markers the V1.43 harness parses")
    func stubEmitsVerifyMarkers() throws {
        let source = try IdempotenceStubEmitter.emit(Self.inputs())
        // Default-pass markers — identical names to RoundTripStubEmitter
        // so VerifyResultParser handles both templates unchanged.
        #expect(source.contains("VERIFY_DEFAULT_RESULT: FAIL"))
        #expect(source.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(source.contains("VERIFY_DEFAULT_TRIAL:"))
        #expect(source.contains("VERIFY_DEFAULT_INPUT:"))
        #expect(source.contains("VERIFY_DEFAULT_FORWARD:"))
        #expect(source.contains("VERIFY_DEFAULT_INVERSE:"))
        #expect(source.contains("VERIFY_DEFAULT_TRIALS:"))
        // Edge-pass markers
        #expect(source.contains("VERIFY_EDGE_RESULT: FAIL"))
        #expect(source.contains("VERIFY_EDGE_RESULT: PASS"))
        #expect(source.contains("VERIFY_EDGE_TRIAL:"))
        #expect(source.contains("VERIFY_EDGE_INPUT:"))
        #expect(source.contains("VERIFY_EDGE_FORWARD:"))
        #expect(source.contains("VERIFY_EDGE_INVERSE:"))
        #expect(source.contains("VERIFY_EDGE_INDEX:"))
        #expect(source.contains("VERIFY_EDGE_TRIALS:"))
        #expect(source.contains("VERIFY_EDGE_SAMPLED:"))
    }

    @Test("stub references the kit's edgeCaseBiased() generator")
    func stubReferencesEdgeCaseBiased() throws {
        let source = try IdempotenceStubEmitter.emit(Self.inputs())
        #expect(source.contains("Gen<Complex<Double>>.edgeCaseBiased()"))
        #expect(source.contains("Gen<Complex<Double>>.complexEdgeCases"))
    }

    @Test("edge-index resolution uses rawStorage (NaN-aware, non-finite-distinguishing)")
    func stubMatchesEdgeIndexViaRawStorage() throws {
        let source = try IdempotenceStubEmitter.emit(Self.inputs())
        // V1.43.E.3.b fix carried into V1.44.A — `.rawStorage` preserves
        // the 8 distinct non-finite curated entries through index
        // resolution.
        #expect(source.contains("value.rawStorage"))
        #expect(!source.contains("entry.real.isNaN"))
    }

    @Test("stub exits 1 on FAIL and 0 on PASS")
    func stubExitsWithCorrectCodes() throws {
        let source = try IdempotenceStubEmitter.emit(Self.inputs())
        #expect(source.contains("exit(1)"))
        #expect(source.contains("exit(0)"))
    }

    // MARK: - V1.44.C carrier dispatch

    @Test("Double carrier emits two-pass stub (no ComplexModule / PropertyLawComplex imports)")
    func doubleCarrierEmits() throws {
        let source = try IdempotenceStubEmitter.emit(
            Self.inputs(functionCall: "abs", carrierType: "Double")
        )
        #expect(!source.isEmpty)
        // Double doesn't need Complex imports.
        #expect(!source.contains("import ComplexModule"))
        #expect(!source.contains("import PropertyLawComplex"))
        #expect(source.contains("import RealModule"))
        #expect(source.contains("import PropertyBased"))
        #expect(source.contains("import Foundation"))
    }

    @Test("Double carrier uses inlined doubleWithNaN equivalent for edge pass")
    func doubleCarrierEdgePassUsesInlinedDoubleWithNaN() throws {
        let source = try IdempotenceStubEmitter.emit(
            Self.inputs(functionCall: "abs", carrierType: "Double")
        )
        #expect(source.contains("Gen<Int>.int(in: 0 ..< 20)"))
        #expect(source.contains("return Double.nan"))
        // Single-entry edge match — NaN → index 0, else -1.
        #expect(source.contains("value.isNaN ? 0 : -1"))
        #expect(!source.contains("complexEdgeCases"))
    }

    @Test("Double carrier renders f(value) and f(onceResult)")
    func doubleCarrierFTwiceCallShape() throws {
        let source = try IdempotenceStubEmitter.emit(
            Self.inputs(functionCall: "abs", carrierType: "Double")
        )
        #expect(source.contains("abs(value)"))
        #expect(source.contains("abs(onceResult)"))
        // Equality is on once vs twice, via the NaN-reflexive oracle
        // (Double `==`/≈ aren't reflexive on NaN; `sameResult` makes them).
        #expect(source.contains("sameResult(twiceResult, onceResult)"))
        #expect(source.contains("func sameResult(_ lhs: Double, _ rhs: Double) -> Bool"))
    }

    @Test("Int carrier emits single-pass stub (no FP / Complex imports)")
    func intCarrierEmits() throws {
        let source = try IdempotenceStubEmitter.emit(
            Self.inputs(functionCall: "abs", carrierType: "Int")
        )
        #expect(!source.isEmpty)
        #expect(!source.contains("import ComplexModule"))
        #expect(!source.contains("import PropertyLawComplex"))
        #expect(!source.contains("import RealModule"))
        #expect(source.contains("import PropertyBased"))
        #expect(source.contains("import Foundation"))
    }

    @Test("Int carrier uses != (not isApproximatelyEqual) for the inequality check")
    func intCarrierUsesExactEquality() throws {
        let source = try IdempotenceStubEmitter.emit(
            Self.inputs(functionCall: "abs", carrierType: "Int")
        )
        #expect(source.contains("twiceResult != onceResult"))
        #expect(!source.contains("isApproximatelyEqual"))
    }

    @Test("Int carrier emits edge-pass sentinel (VERIFY_EDGE_TRIALS: 0)")
    func intCarrierEmitsEdgeSentinel() throws {
        let source = try IdempotenceStubEmitter.emit(
            Self.inputs(functionCall: "abs", carrierType: "Int")
        )
        #expect(source.contains("VERIFY_EDGE_RESULT: PASS"))
        #expect(source.contains("VERIFY_EDGE_TRIALS: 0"))
        #expect(source.contains("VERIFY_EDGE_SAMPLED: 0"))
        #expect(!source.contains("VERIFY_EDGE_TRIAL:"))
        #expect(!source.contains("VERIFY_EDGE_INDEX:"))
    }

    // MARK: - V1.141 shrink phase

    @Test("Complex<Double> default pass shrinks the failing input on idempotence failure")
    func complexCarrierEmitsShrinkPhase() throws {
        let source = try IdempotenceStubEmitter.emit(Self.inputs())
        #expect(source.contains("VERIFY_DEFAULT_SHRUNK:"))
        #expect(source.contains("VERIFY_SHRINK_STEPS:"))
        #expect(source.contains("func idempotenceFails"))
        #expect(source.contains("shrunk.real.shrink(towards: 0)"))
        #expect(source.contains("shrunk.imaginary.shrink(towards: 0)"))
    }

    @Test("Double / Int default passes shrink the failing input toward 0")
    func scalarCarriersEmitShrinkPhase() throws {
        let doubleSource = try IdempotenceStubEmitter.emit(
            Self.inputs(functionCall: "abs", carrierType: "Double")
        )
        #expect(doubleSource.contains("VERIFY_DEFAULT_SHRUNK:"))
        #expect(doubleSource.contains("shrunk.shrink(towards: 0)"))

        let intSource = try IdempotenceStubEmitter.emit(
            Self.inputs(functionCall: "abs", carrierType: "Int")
        )
        #expect(intSource.contains("VERIFY_DEFAULT_SHRUNK:"))
        #expect(intSource.contains("shrunk.shrink(towards: 0)"))
        // Int oracle is exact inequality.
        #expect(intSource.contains("!= onceCandidate"))
    }
}
