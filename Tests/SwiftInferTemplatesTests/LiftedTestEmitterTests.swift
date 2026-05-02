import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

// swiftlint:disable type_body_length file_length line_length
// Suite coheres around its subject — the byte-stable goldens for each
// emitter arm are inherently long string literals; splitting along the
// 250-line body limit would scatter the goldens across multiple files
// for no reader benefit. file_length disable for the same reason
// (M8.2 added four arms — eight goldens total now exceed the 400-line
// cap by an unavoidable margin). line_length disable because the
// associativity property closure (one byte-stable golden) renders to
// 132 chars on a single line — the closure body is one expression and
// breaking it would drift the golden away from the actual emitter
// output, defeating the byte-stability guarantee.
@Suite("LiftedTestEmitter — pure-function lifted-test source emit (M6.3 + M7.3)")
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

    // MARK: - commutative(...) byte-stable golden (M8.2)

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

    // MARK: - associative(...) byte-stable golden (M8.2)

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
                    property: { triple in merge(merge(triple.0, triple.1), triple.2) == merge(triple.0, merge(triple.1, triple.2)) }
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

    // MARK: - identityElement(...) byte-stable golden (M8.2)

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

    // MARK: - inversePair(...) byte-stable golden (M8.2)

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
// swiftlint:enable type_body_length file_length line_length
