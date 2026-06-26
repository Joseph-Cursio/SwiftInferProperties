import Foundation
import Testing

@testable import SwiftInferCLI

/// V1.42.C.2 — RoundTripStubEmitter unit tests.
///
/// The stub source is a string; tests pin the load-bearing pieces
/// (mandatory imports, forward/inverse call expressions, seed
/// hex-formatting, trial-budget literal, the `VERIFY_RESULT:` output
/// markers V1.42.C.4 will parse) rather than the full text — golden-
/// file matching would be brittle across formatting tweaks. V1.42.D
/// integration tests cover compile-and-run.
@Suite("RoundTripStubEmitter — V1.42.C.2 stub emission")
struct RoundTripStubEmitterTests {

    private static let canonicalSeed = RoundTripStubEmitter.SeedHex(
        stateA: 0xDEAD_BEEF_CAFE_BABE,
        stateB: 0x0123_4567_89AB_CDEF,
        stateC: 0xFEDC_BA98_7654_3210,
        stateD: 0xAAAA_BBBB_CCCC_DDDD
    )

    private static func inputs(
        forwardCall: String = "Complex.exp",
        inverseCall: String = "Complex.log",
        extraImports: [String] = [],
        carrierType: String = "Complex<Double>",
        trialBudget: RoundTripStubEmitter.TrialBudget = .small
    ) -> RoundTripStubEmitter.Inputs {
        RoundTripStubEmitter.Inputs(
            forwardCall: forwardCall,
            inverseCall: inverseCall,
            extraImports: extraImports,
            carrierType: carrierType,
            seedHex: canonicalSeed,
            trialBudget: trialBudget
        )
    }

    // MARK: - Carrier validation

    @Test("Complex<Double> carrier compiles to a stub")
    func complexDoubleCarrierEmits() throws {
        let source = try RoundTripStubEmitter.emit(Self.inputs())
        #expect(!source.isEmpty)
    }

    @Test("non-Complex<Double> carrier raises .unsupportedCarrier")
    func unsupportedCarrierThrows() throws {
        do {
            _ = try RoundTripStubEmitter.emit(Self.inputs(carrierType: "Array<Int>"))
            Issue.record("expected .unsupportedCarrier")
        } catch let error as VerifyError {
            switch error {
            case let .unsupportedCarrier(carrier, expected):
                #expect(carrier == "Array<Int>")
                #expect(expected == RoundTripStubEmitter.supportedCarriers)

            default:
                Issue.record("expected .unsupportedCarrier; got \(error)")
            }
        }
    }

    @Test("supportedCarriers contains all three V1.44.B carriers")
    func supportedCarriersListIsLoadBearing() {
        #expect(RoundTripStubEmitter.supportedCarriers.contains("Complex<Double>"))
        #expect(RoundTripStubEmitter.supportedCarriers.contains("Double"))
        #expect(RoundTripStubEmitter.supportedCarriers.contains("Int"))
    }

    // MARK: - Mandatory imports

    @Test("stub imports the mandatory modules (V1.42 + V1.43.A)")
    func stubContainsMandatoryImports() throws {
        let source = try RoundTripStubEmitter.emit(Self.inputs())
        #expect(source.contains("import ComplexModule"))
        #expect(source.contains("import RealModule"))
        #expect(source.contains("import PropertyBased"))
        #expect(source.contains("import PropertyLawComplex"))
        #expect(source.contains("import Foundation"))
    }

    @Test("stub appends caller-supplied extra imports without duplication")
    func stubMergesExtraImports() throws {
        let source = try RoundTripStubEmitter.emit(
            Self.inputs(extraImports: ["MyTarget", "ComplexModule", "  ", ""])
        )
        // ComplexModule was a mandatory import — even when the caller
        // also passes it, the import line appears only once.
        let occurrences = source.components(separatedBy: "import ComplexModule").count - 1
        #expect(occurrences == 1)
        #expect(source.contains("import MyTarget"))
    }

    // MARK: - Forward / inverse calls

    @Test("stub renders forward(value) and inverse(forward(value))")
    func forwardInverseCallShape() throws {
        let source = try RoundTripStubEmitter.emit(
            Self.inputs(forwardCall: "Complex.exp", inverseCall: "Complex.log")
        )
        #expect(source.contains("Complex.exp(value)"))
        #expect(source.contains("Complex.log(forwardResult)"))
    }

    // MARK: - Equality assertion

    @Test("equality uses isApproximatelyEqual, not ==")
    func equalityIsApproximate() throws {
        let source = try RoundTripStubEmitter.emit(Self.inputs())
        #expect(source.contains("isApproximatelyEqual"))
        // The strict `!=` operator would be on the line `if value !=` —
        // we deliberately don't emit that form for FP round-trips.
        #expect(!source.contains("if inverseResult !="))
    }

    // MARK: - Seed hex formatting

    @Test("seed components render as uppercase hex")
    func seedRendersAsUppercaseHex() throws {
        let source = try RoundTripStubEmitter.emit(Self.inputs())
        #expect(source.contains("0xDEADBEEFCAFEBABE"))
        #expect(source.contains("0x123456789ABCDEF"))
        #expect(source.contains("0xFEDCBA9876543210"))
        #expect(source.contains("0xAAAABBBBCCCCDDDD"))
    }

    // MARK: - Trial budget

    @Test("small budget renders trials = 100")
    func smallBudgetRendersAsHundred() throws {
        let source = try RoundTripStubEmitter.emit(Self.inputs(trialBudget: .small))
        #expect(source.contains("let trials = 100"))
    }

    @Test("standard budget renders trials = 1000")
    func standardBudgetRendersAsThousand() throws {
        let source = try RoundTripStubEmitter.emit(Self.inputs(trialBudget: .standard))
        #expect(source.contains("let trials = 1000"))
    }

    // MARK: - V1.43.B two-pass result markers

    @Test("stub emits the per-pass VERIFY_* markers the harness parses")
    func stubEmitsVerifyResultMarkers() throws {
        let source = try RoundTripStubEmitter.emit(Self.inputs())
        // Pass 1 (default) marker surface
        #expect(source.contains("VERIFY_DEFAULT_RESULT: FAIL"))
        #expect(source.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(source.contains("VERIFY_DEFAULT_TRIAL:"))
        #expect(source.contains("VERIFY_DEFAULT_INPUT:"))
        #expect(source.contains("VERIFY_DEFAULT_FORWARD:"))
        #expect(source.contains("VERIFY_DEFAULT_INVERSE:"))
        #expect(source.contains("VERIFY_DEFAULT_TRIALS:"))
        // Pass 2 (edge) marker surface
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
        let source = try RoundTripStubEmitter.emit(Self.inputs())
        #expect(source.contains("Gen<Complex<Double>>.edgeCaseBiased()"))
        #expect(source.contains("Gen<Complex<Double>>.complexEdgeCases"))
    }

    @Test("edge-index resolution uses rawStorage (NaN-aware, non-finite-distinguishing)")
    func stubMatchesEdgeIndexViaRawStorage() throws {
        let source = try RoundTripStubEmitter.emit(Self.inputs())
        // The .real / .imaginary getters collapse to .nan for any
        // non-finite Complex, so they can't distinguish entries #0–#7.
        // Use .rawStorage instead — the load-bearing accessor for
        // edge-case-index resolution.
        #expect(source.contains("value.rawStorage"))
        #expect(source.contains(".rawStorage"))
        #expect(!source.contains("entry.real.isNaN"))
        #expect(!source.contains("entry.imaginary.isNaN"))
    }

    @Test("stub exits 1 on FAIL and 0 on PASS")
    func stubExitsWithCorrectCodes() throws {
        let source = try RoundTripStubEmitter.emit(Self.inputs())
        #expect(source.contains("exit(1)"))
        #expect(source.contains("exit(0)"))
    }

    // MARK: - V1.44.B carrier dispatch

    @Test("Double carrier emits two-pass stub (no ComplexModule / PropertyLawComplex imports)")
    func doubleCarrierEmits() throws {
        let source = try RoundTripStubEmitter.emit(
            Self.inputs(forwardCall: "double", inverseCall: "double", carrierType: "Double")
        )
        #expect(!source.isEmpty)
        // Double doesn't need Complex imports.
        #expect(!source.contains("import ComplexModule"))
        #expect(!source.contains("import PropertyLawComplex"))
        #expect(source.contains("import RealModule"))
        #expect(source.contains("import PropertyBased"))
        #expect(source.contains("import Foundation"))
    }

    @Test("Double carrier uses inlined doubleWithNaN equivalent (NaN at ~5%) for edge pass")
    func doubleCarrierEdgePassUsesInlinedDoubleWithNaN() throws {
        let source = try RoundTripStubEmitter.emit(
            Self.inputs(forwardCall: "abs", inverseCall: "abs", carrierType: "Double")
        )
        // The inlined doubleWithNaN: Gen<Int>.int(in: 0 ..< 20).map { tag → NaN at tag==0 }
        #expect(source.contains("Gen<Int>.int(in: 0 ..< 20)"))
        #expect(source.contains("return Double.nan"))
        // Single-entry edge match — NaN → index 0, else -1.
        #expect(source.contains("value.isNaN ? 0 : -1"))
        // No Complex-specific edge match.
        #expect(!source.contains("complexEdgeCases"))
    }

    @Test("Double carrier emits two-pass + VERIFY_EDGE_INDEX marker")
    func doubleCarrierEmitsTwoPassMarkers() throws {
        let source = try RoundTripStubEmitter.emit(
            Self.inputs(forwardCall: "abs", inverseCall: "abs", carrierType: "Double")
        )
        #expect(source.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(source.contains("VERIFY_EDGE_RESULT: PASS"))
        #expect(source.contains("VERIFY_EDGE_INDEX:"))
        #expect(source.contains("VERIFY_EDGE_SAMPLED:"))
    }

    @Test("Int carrier emits single-pass stub (no FP / Complex imports)")
    func intCarrierEmits() throws {
        let source = try RoundTripStubEmitter.emit(
            Self.inputs(forwardCall: "negate", inverseCall: "negate", carrierType: "Int")
        )
        #expect(!source.isEmpty)
        // Int doesn't need any FP / Complex imports.
        #expect(!source.contains("import ComplexModule"))
        #expect(!source.contains("import PropertyLawComplex"))
        #expect(!source.contains("import RealModule"))
        #expect(source.contains("import PropertyBased"))
        #expect(source.contains("import Foundation"))
    }

    @Test("Int carrier uses == (not isApproximatelyEqual) for equality check")
    func intCarrierUsesExactEquality() throws {
        let source = try RoundTripStubEmitter.emit(
            Self.inputs(forwardCall: "negate", inverseCall: "negate", carrierType: "Int")
        )
        #expect(source.contains("inverseResult != value"))
        #expect(!source.contains("isApproximatelyEqual"))
    }

    @Test("Int carrier emits edge-pass sentinel (VERIFY_EDGE_TRIALS: 0)")
    func intCarrierEmitsEdgeSentinel() throws {
        let source = try RoundTripStubEmitter.emit(
            Self.inputs(forwardCall: "negate", inverseCall: "negate", carrierType: "Int")
        )
        // Single-pass: emit zero-edge sentinel so VerifyResultParser
        // still produces .bothPass (with edgeTrials: 0, edgeSampled: 0).
        #expect(source.contains("VERIFY_EDGE_RESULT: PASS"))
        #expect(source.contains("VERIFY_EDGE_TRIALS: 0"))
        #expect(source.contains("VERIFY_EDGE_SAMPLED: 0"))
        // No per-trial edge loop / index marker.
        #expect(!source.contains("VERIFY_EDGE_TRIAL:"))
        #expect(!source.contains("VERIFY_EDGE_INDEX:"))
    }

    // MARK: - V1.141 shrink phase (minimal counterexamples)

    @Test("Complex<Double> default pass shrinks each component toward 0 on failure")
    func complexCarrierEmitsShrinkPhase() throws {
        let source = try RoundTripStubEmitter.emit(Self.inputs())
        #expect(source.contains("VERIFY_DEFAULT_SHRUNK:"))
        #expect(source.contains("VERIFY_SHRINK_STEPS:"))
        #expect(source.contains("func roundTripFails"))
        // One component at a time, toward zero.
        #expect(source.contains("shrunk.real.shrink(towards: 0)"))
        #expect(source.contains("shrunk.imaginary.shrink(towards: 0)"))
    }

    @Test("Double default pass shrinks the value toward 0 on failure")
    func doubleCarrierEmitsShrinkPhase() throws {
        let source = try RoundTripStubEmitter.emit(
            Self.inputs(forwardCall: "abs", inverseCall: "abs", carrierType: "Double")
        )
        #expect(source.contains("VERIFY_DEFAULT_SHRUNK:"))
        #expect(source.contains("VERIFY_SHRINK_STEPS:"))
        #expect(source.contains("shrunk.shrink(towards: 0)"))
    }

    @Test("Int default pass shrinks the value toward 0 on failure (exact equality oracle)")
    func intCarrierEmitsShrinkPhase() throws {
        let source = try RoundTripStubEmitter.emit(
            Self.inputs(forwardCall: "negate", inverseCall: "negate", carrierType: "Int")
        )
        #expect(source.contains("VERIFY_DEFAULT_SHRUNK:"))
        #expect(source.contains("VERIFY_SHRINK_STEPS:"))
        #expect(source.contains("shrunk.shrink(towards: 0)"))
        // Int oracle is exact inequality, not isApproximatelyEqual.
        #expect(source.contains("!= candidate"))
    }
}
