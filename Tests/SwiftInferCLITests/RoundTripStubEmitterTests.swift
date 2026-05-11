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
                #expect(expected == ["Complex<Double>"])
            default:
                Issue.record("expected .unsupportedCarrier; got \(error)")
            }
        }
    }

    @Test("supportedCarriers contains Complex<Double>")
    func supportedCarriersListIsLoadBearing() {
        #expect(RoundTripStubEmitter.supportedCarriers.contains("Complex<Double>"))
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

    @Test("stub exits 1 on FAIL and 0 on PASS")
    func stubExitsWithCorrectCodes() throws {
        let source = try RoundTripStubEmitter.emit(Self.inputs())
        #expect(source.contains("exit(1)"))
        #expect(source.contains("exit(0)"))
    }
}
