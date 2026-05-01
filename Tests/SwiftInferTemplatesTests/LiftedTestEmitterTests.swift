import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("LiftedTestEmitter — pure-function lifted-test source emit (M6.3)")
struct LiftedTestEmitterTests {

    // MARK: - defaultGenerator(for:)

    @Test
    func defaultGeneratorForIntPicksRawTypeIntGenerator() {
        #expect(LiftedTestEmitter.defaultGenerator(for: "Int") == "Gen<Int>.int()")
    }

    @Test
    func defaultGeneratorForStringPicksRawTypeStringGenerator() {
        #expect(LiftedTestEmitter.defaultGenerator(for: "String")
            == "Gen<Character>.letterOrNumber.string(of: 0...8)")
    }

    @Test
    func defaultGeneratorForCustomTypeFallsBackToUserGen() {
        // Same `.userGen` fallback `DerivationStrategist` produces —
        // requires the user to provide `static func gen() -> Gen<T>`
        // on the type or take the resulting compile error.
        #expect(LiftedTestEmitter.defaultGenerator(for: "MyType") == "MyType.gen()")
    }

    // MARK: - idempotent(...) byte-stable golden

    @Test
    func idempotentEmitsByteStableTestStub() {
        let seed = SamplingSeed.Value(
            stateA: 0x0123456789ABCDEF,
            stateB: 0xFEDCBA9876543210,
            stateC: 0x1111111111111111,
            stateD: 0x2222222222222222
        )
        let source = LiftedTestEmitter.idempotent(
            funcName: "normalize",
            typeName: "String",
            seed: seed,
            generator: "Gen<Character>.letterOrNumber.string(of: 0...8)"
        )
        let expected = """

            @Test func normalize_isIdempotent() async {
                let backend = SwiftPropertyBasedBackend()
                let seed = Seed(
                    stateA: 0x0123456789ABCDEF,
                    stateB: 0xFEDCBA9876543210,
                    stateC: 0x1111111111111111,
                    stateD: 0x2222222222222222
                )
                let result = await backend.check(
                    trials: 100,
                    seed: seed,
                    sample: { rng in (Gen<Character>.letterOrNumber.string(of: 0...8)).run(&rng) },
                    property: { value in normalize(normalize(value)) == normalize(value) }
                )
                if case let .failed(_, _, input, error) = result {
                    Issue.record(
                        "normalize(_:) failed idempotence at input \\(input)."
                            + " \\(error?.message ?? \\"\\")"
                    )
                }
            }
            """
        #expect(source == expected)
    }

    // MARK: - roundTrip(...) byte-stable golden

    @Test
    func roundTripEmitsByteStableTestStub() {
        let seed = SamplingSeed.Value(
            stateA: 0xAAAAAAAAAAAAAAAA,
            stateB: 0xBBBBBBBBBBBBBBBB,
            stateC: 0xCCCCCCCCCCCCCCCC,
            stateD: 0xDDDDDDDDDDDDDDDD
        )
        let source = LiftedTestEmitter.roundTrip(
            forwardName: "encode",
            inverseName: "decode",
            seed: seed,
            generator: "MyType.gen()"
        )
        let expected = """

            @Test func encode_decode_roundTrip() async {
                let backend = SwiftPropertyBasedBackend()
                let seed = Seed(
                    stateA: 0xAAAAAAAAAAAAAAAA,
                    stateB: 0xBBBBBBBBBBBBBBBB,
                    stateC: 0xCCCCCCCCCCCCCCCC,
                    stateD: 0xDDDDDDDDDDDDDDDD
                )
                let result = await backend.check(
                    trials: 100,
                    seed: seed,
                    sample: { rng in (MyType.gen()).run(&rng) },
                    property: { value in decode(encode(value)) == value }
                )
                if case let .failed(_, _, input, error) = result {
                    Issue.record(
                        "encode/decode round-trip failed at input \\(input)."
                            + " \\(error?.message ?? \\"\\")"
                    )
                }
            }
            """
        #expect(source == expected)
    }

    // MARK: - Determinism

    @Test
    func sameInputsProduceByteIdenticalSource() {
        let seed = SamplingSeed.derive(
            fromIdentityHash: "checkProperty.idempotent|normalize|(String)->String"
        )
        let first = LiftedTestEmitter.idempotent(
            funcName: "normalize",
            typeName: "String",
            seed: seed,
            generator: LiftedTestEmitter.defaultGenerator(for: "String")
        )
        let second = LiftedTestEmitter.idempotent(
            funcName: "normalize",
            typeName: "String",
            seed: seed,
            generator: LiftedTestEmitter.defaultGenerator(for: "String")
        )
        #expect(first == second)
    }

    // MARK: - Cross-arm independence

    @Test
    func idempotentAndRoundTripProduceDistinctSource() {
        // Same function name in both arms must produce different
        // stub bodies (different test-function names, different
        // property assertions).
        let seed = SamplingSeed.Value(stateA: 1, stateB: 2, stateC: 3, stateD: 4)
        let idempotentSource = LiftedTestEmitter.idempotent(
            funcName: "transform",
            typeName: "Int",
            seed: seed,
            generator: "Gen<Int>.int()"
        )
        let roundTripSource = LiftedTestEmitter.roundTrip(
            forwardName: "transform",
            inverseName: "untransform",
            seed: seed,
            generator: "Gen<Int>.int()"
        )
        #expect(idempotentSource != roundTripSource)
        #expect(idempotentSource.contains("transform_isIdempotent"))
        #expect(roundTripSource.contains("transform_untransform_roundTrip"))
    }
}
