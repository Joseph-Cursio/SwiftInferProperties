import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("LiftedTestEmitter — M8.2 algebraic-structure arms")
struct LiftedTestEmitterM8Tests {

    // MARK: - commutative(...) byte-stable golden

    @Test
    func commutativeEmitsByteStableTestStub() {
        let seed = SamplingSeed.Value(
            stateA: 0x1111_2222_3333_4444,
            stateB: 0x5555_6666_7777_8888,
            stateC: 0x9999_AAAA_BBBB_CCCC,
            stateD: 0xDDDD_EEEE_FFFF_0000
        )
        let source = LiftedTestEmitter.commutative(
            funcName: "merge",
            typeName: "IntSet",
            seed: seed,
            generator: "IntSet.gen()"
        )
        let expected = """

            @Test func merge_isCommutative() async {
                let backend = SwiftPropertyBasedBackend()
                let seed = Seed(
                    stateA: 0x1111222233334444,
                    stateB: 0x5555666677778888,
                    stateC: 0x9999AAAABBBBCCCC,
                    stateD: 0xDDDDEEEEFFFF0000
                )
                let result = await backend.check(
                    trials: 100,
                    seed: seed,
                    sample: { rng in
                                let lhs = (IntSet.gen()).run(&rng)
                                let rhs = (IntSet.gen()).run(&rng)
                                return (lhs, rhs)
                            },
                    property: { pair in merge(pair.0, pair.1) == merge(pair.1, pair.0) }
                )
                if case let .failed(_, _, input, error) = result {
                    Issue.record(
                        "merge(_:_:) failed commutativity at input \\(input)."
                            + " \\(error?.message ?? \\"\\")"
                    )
                }
            }
            """
        #expect(source == expected)
    }

    // MARK: - associative(...) byte-stable golden

    @Test
    func associativeEmitsByteStableTestStub() {
        let seed = SamplingSeed.Value(
            stateA: 0x1111_2222_3333_4444,
            stateB: 0x5555_6666_7777_8888,
            stateC: 0x9999_AAAA_BBBB_CCCC,
            stateD: 0xDDDD_EEEE_FFFF_0000
        )
        let source = LiftedTestEmitter.associative(
            funcName: "merge",
            typeName: "IntSet",
            seed: seed,
            generator: "IntSet.gen()"
        )
        let expected = """

            @Test func merge_isAssociative() async {
                let backend = SwiftPropertyBasedBackend()
                let seed = Seed(
                    stateA: 0x1111222233334444,
                    stateB: 0x5555666677778888,
                    stateC: 0x9999AAAABBBBCCCC,
                    stateD: 0xDDDDEEEEFFFF0000
                )
                let result = await backend.check(
                    trials: 100,
                    seed: seed,
                    sample: { rng in
                                let one = (IntSet.gen()).run(&rng)
                                let two = (IntSet.gen()).run(&rng)
                                let three = (IntSet.gen()).run(&rng)
                                return (one, two, three)
                            },
                    property: { triple in
                        merge(merge(triple.0, triple.1), triple.2)
                            == merge(triple.0, merge(triple.1, triple.2))
                    }
                )
                if case let .failed(_, _, input, error) = result {
                    Issue.record(
                        "merge(_:_:) failed associativity at input \\(input)."
                            + " \\(error?.message ?? \\"\\")"
                    )
                }
            }
            """
        #expect(source == expected)
    }

    // MARK: - identityElement(...) byte-stable golden

    @Test
    func identityElementEmitsByteStableTestStub() {
        let seed = SamplingSeed.Value(
            stateA: 0x1111_2222_3333_4444,
            stateB: 0x5555_6666_7777_8888,
            stateC: 0x9999_AAAA_BBBB_CCCC,
            stateD: 0xDDDD_EEEE_FFFF_0000
        )
        let source = LiftedTestEmitter.identityElement(
            funcName: "merge",
            typeName: "IntSet",
            identityName: "empty",
            seed: seed,
            generator: "IntSet.gen()"
        )
        let expected = """

            @Test func merge_hasIdentity_empty() async {
                let backend = SwiftPropertyBasedBackend()
                let seed = Seed(
                    stateA: 0x1111222233334444,
                    stateB: 0x5555666677778888,
                    stateC: 0x9999AAAABBBBCCCC,
                    stateD: 0xDDDDEEEEFFFF0000
                )
                let result = await backend.check(
                    trials: 100,
                    seed: seed,
                    sample: { rng in (IntSet.gen()).run(&rng) },
                    property: { value in merge(value, IntSet.empty) == value && merge(IntSet.empty, value) == value }
                )
                if case let .failed(_, _, input, error) = result {
                    Issue.record(
                        "merge(_:_:) failed identity-element IntSet.empty at input \\(input)."
                            + " \\(error?.message ?? \\"\\")"
                    )
                }
            }
            """
        #expect(source == expected)
    }

    // MARK: - inversePair(...) byte-stable golden

    @Test
    func inversePairEmitsByteStableTestStub() {
        let seed = SamplingSeed.Value(
            stateA: 0x1111_2222_3333_4444,
            stateB: 0x5555_6666_7777_8888,
            stateC: 0x9999_AAAA_BBBB_CCCC,
            stateD: 0xDDDD_EEEE_FFFF_0000
        )
        let source = LiftedTestEmitter.inversePair(
            forwardName: "encode",
            inverseName: "decode",
            typeName: "MyType",
            seed: seed,
            generator: "MyType.gen()"
        )
        let expected = """

            @Test func encode_decode_inversePair() async {
                let backend = SwiftPropertyBasedBackend()
                let seed = Seed(
                    stateA: 0x1111222233334444,
                    stateB: 0x5555666677778888,
                    stateC: 0x9999AAAABBBBCCCC,
                    stateD: 0xDDDDEEEEFFFF0000
                )
                let result = await backend.check(
                    trials: 100,
                    seed: seed,
                    sample: { rng in (MyType.gen()).run(&rng) },
                    property: { value in decode(encode(value)) == value }
                )
                if case let .failed(_, _, input, error) = result {
                    Issue.record(
                        "encode/decode inverse-pair failed at input \\(input)."
                            + " \\(error?.message ?? \\"\\")"
                    )
                }
            }
            """
        #expect(source == expected)
    }

    @Test
    func inversePairAndRoundTripProduceDistinctSource() {
        // Same forward/inverse names — different test-function name and
        // failure label so a single suggestion accept doesn't collide
        // when the user has both M1.4 round-trip (Equatable T) and M8.1
        // inverse-pair (non-Equatable T) suggestions on differently-typed
        // pairs in the same project.
        let seed = SamplingSeed.Value(stateA: 1, stateB: 2, stateC: 3, stateD: 4)
        let roundTripSource = LiftedTestEmitter.roundTrip(
            forwardName: "encode",
            inverseName: "decode",
            seed: seed,
            generator: "MyType.gen()"
        )
        let inversePairSource = LiftedTestEmitter.inversePair(
            forwardName: "encode",
            inverseName: "decode",
            typeName: "MyType",
            seed: seed,
            generator: "MyType.gen()"
        )
        #expect(roundTripSource != inversePairSource)
        #expect(roundTripSource.contains("encode_decode_roundTrip"))
        #expect(inversePairSource.contains("encode_decode_inversePair"))
        #expect(roundTripSource.contains("encode/decode round-trip failed"))
        #expect(inversePairSource.contains("encode/decode inverse-pair failed"))
    }

    @Test
    func commutativeAndAssociativeProduceDistinctSource() {
        let seed = SamplingSeed.Value(stateA: 1, stateB: 2, stateC: 3, stateD: 4)
        let commutativeSource = LiftedTestEmitter.commutative(
            funcName: "merge",
            typeName: "IntSet",
            seed: seed,
            generator: "IntSet.gen()"
        )
        let associativeSource = LiftedTestEmitter.associative(
            funcName: "merge",
            typeName: "IntSet",
            seed: seed,
            generator: "IntSet.gen()"
        )
        #expect(commutativeSource != associativeSource)
        #expect(commutativeSource.contains("merge_isCommutative"))
        #expect(associativeSource.contains("merge_isAssociative"))
        // Commutative samples a pair, associative samples a triple —
        // the marker is the third generator draw line in associativity.
        #expect(associativeSource.contains("let three = "))
        #expect(commutativeSource.contains("let three = ") == false)
    }
}
