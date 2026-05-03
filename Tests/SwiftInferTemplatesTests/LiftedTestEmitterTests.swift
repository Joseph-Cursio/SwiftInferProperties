import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("LiftedTestEmitter — defaultGenerator + M6.3 arms (idempotent, roundTrip)")
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

@Suite("LiftedTestEmitter — M7.3 arms (monotonic, invariantPreserving)")
struct LiftedTestEmitterM7Tests {

    // MARK: - monotonic(...) byte-stable golden (M7.3)

    @Test
    func monotonicEmitsByteStableTestStub() {
        let seed = SamplingSeed.Value(
            stateA: 0xAAAA_BBBB_CCCC_DDDD,
            stateB: 0xEEEE_FFFF_0000_1111,
            stateC: 0x2222_3333_4444_5555,
            stateD: 0x6666_7777_8888_9999
        )
        let source = LiftedTestEmitter.monotonic(
            funcName: "length",
            typeName: "String",
            returnType: "Int",
            seed: seed,
            generator: "Gen<Character>.letterOrNumber.string(of: 0...8)"
        )
        let expected = """

            @Test func length_isMonotonic() async {
                let backend = SwiftPropertyBasedBackend()
                let seed = Seed(
                    stateA: 0xAAAABBBBCCCCDDDD,
                    stateB: 0xEEEEFFFF00001111,
                    stateC: 0x2222333344445555,
                    stateD: 0x6666777788889999
                )
                let result = await backend.check(
                    trials: 100,
                    seed: seed,
                    sample: { rng in
                                let lhs = (Gen<Character>.letterOrNumber.string(of: 0...8)).run(&rng)
                                let rhs = (Gen<Character>.letterOrNumber.string(of: 0...8)).run(&rng)
                                return lhs < rhs ? (lhs, rhs) : (rhs, lhs)
                            },
                    property: { pair in length(pair.0) <= length(pair.1) }
                )
                if case let .failed(_, _, input, error) = result {
                    Issue.record(
                        "length(_:) failed monotonicity at input \\(input)."
                            + " \\(error?.message ?? \\"\\")"
                    )
                }
            }
            """
        #expect(source == expected)
    }

    // MARK: - invariantPreserving(...) byte-stable golden (M7.3)

    @Test
    func invariantPreservingEmitsByteStableTestStub() {
        let seed = SamplingSeed.Value(
            stateA: 0x1010_1010_1010_1010,
            stateB: 0x2020_2020_2020_2020,
            stateC: 0x3030_3030_3030_3030,
            stateD: 0x4040_4040_4040_4040
        )
        let source = LiftedTestEmitter.invariantPreserving(
            funcName: "adjust",
            typeName: "Widget",
            invariantName: "\\.isValid",
            seed: seed,
            generator: "Widget.gen()"
        )
        let expected = """

            @Test func adjust_preservesInvariant_isValid() async {
                let backend = SwiftPropertyBasedBackend()
                let seed = Seed(
                    stateA: 0x1010101010101010,
                    stateB: 0x2020202020202020,
                    stateC: 0x3030303030303030,
                    stateD: 0x4040404040404040
                )
                let result = await backend.check(
                    trials: 100,
                    seed: seed,
                    sample: { rng in (Widget.gen()).run(&rng) },
                    property: { value in !value[keyPath: \\.isValid] || adjust(value)[keyPath: \\.isValid] }
                )
                if case let .failed(_, _, input, error) = result {
                    Issue.record(
                        "adjust(_:) failed invariant preservation \\.isValid at input \\(input)."
                            + " \\(error?.message ?? \\"\\")"
                    )
                }
            }
            """
        #expect(source == expected)
    }

    @Test
    func invariantPreservingSanitizesNestedKeypathInTestName() {
        let seed = SamplingSeed.Value(stateA: 1, stateB: 2, stateC: 3, stateD: 4)
        let source = LiftedTestEmitter.invariantPreserving(
            funcName: "transfer",
            typeName: "User",
            invariantName: "\\.account.balance",
            seed: seed,
            generator: "User.gen()"
        )
        // Test-function name strips the leading `\.` and rewrites `.`
        // separators as `_` so the identifier is valid Swift.
        #expect(source.contains("transfer_preservesInvariant_account_balance"))
        // The keypath itself remains verbatim inside the property closure.
        #expect(source.contains("[keyPath: \\.account.balance]"))
    }

    @Test
    func monotonicAndInvariantPreservingProduceDistinctSource() {
        let seed = SamplingSeed.Value(stateA: 1, stateB: 2, stateC: 3, stateD: 4)
        let monotonicSource = LiftedTestEmitter.monotonic(
            funcName: "score",
            typeName: "Widget",
            returnType: "Int",
            seed: seed,
            generator: "Widget.gen()"
        )
        let invariantSource = LiftedTestEmitter.invariantPreserving(
            funcName: "score",
            typeName: "Widget",
            invariantName: "\\.isValid",
            seed: seed,
            generator: "Widget.gen()"
        )
        #expect(monotonicSource != invariantSource)
        #expect(monotonicSource.contains("score_isMonotonic"))
        #expect(invariantSource.contains("score_preservesInvariant_isValid"))
    }
}
