import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("LiftedTestEmitter — defaultGenerator + M6.3 arms (idempotent, roundTrip)")
struct LiftedTestEmitterTests {

    // MARK: - defaultGenerator(for:)

    @Test
    func defaultGeneratorForIntPicksRawTypeIntGenerator() {
        #expect(LiftedTestEmitter.defaultGenerator(for: "Int") == "Gen<Int>.int()")
    }

    /// **This test used to pin the defect** (#416). It asserted the plain
    /// `Gen<Character>.letterOrNumber.string(of: 0...8)` — alphanumerics and nothing else — for
    /// the top-level String carrier. 11 of the 19 stubs emitted for SwiftMarkdownWiki drew from
    /// it, and every one of those eleven subjects parses delimiters, so their laws were vacuous:
    /// `strippingHeadingMarkers` is a no-op on all 3 907 alphanumeric strings of length 0–2.
    ///
    /// The `verify` path had already reached for the edge-biased expression and said why in a
    /// comment. This path had not been told.
    @Test
    func defaultGeneratorForStringIsEdgeBiased() {
        let generator = LiftedTestEmitter.defaultGenerator(for: "String")
        // The alphanumeric baseline is kept — the bias mixes, it does not replace.
        #expect(generator.contains("Gen<Character>.letterOrNumber.string(of: 0...8)"))
        #expect(generator.hasPrefix("Gen.frequency("))
        // The characters whose absence made the eleven laws vacuous.
        #expect(generator.contains("\"#\""))
        #expect(generator.contains("\" \""))
        #expect(generator.contains("\"\\n\""))
    }

    /// Every non-`RawType` carrier is the "you supply it" arm, and it now says so. Four of the
    /// nineteen emitted stubs were this arm — `CGFloat`, `URL`, `Date?`, `[PluginLogEntry]` —
    /// emitted with nothing to distinguish them from a resolved generator.
    @Test
    func defaultGeneratorForCustomTypeFallsBackToUserGenAndSaysSo() {
        let generator = LiftedTestEmitter.defaultGenerator(for: "MyType")
        #expect(generator.hasPrefix("MyType.gen()"))
        #expect(generator.contains("no generator derived"))
    }

    /// **A block comment, because the generator is spliced into an expression.** The emitters
    /// wrap it as `{ rng in (<generator>).run(using: &rng) }`, so a `//` marker would swallow
    /// `.run(using: &rng) }` — breaking the file for a reason unrelated to the missing generator.
    /// The first draft of the marker did exactly that.
    @Test
    func theTodoMarkerIsSafeToSpliceIntoAnExpression() {
        let generator = LiftedTestEmitter.defaultGenerator(for: "MyType")
        #expect(generator.contains("//") == false)
        #expect(generator.hasSuffix("*/"))
        // The shape the emitters actually build, with the marker inside the parentheses.
        let spliced = "{ rng in (\(generator)).run(using: &rng) }"
        #expect(spliced.hasSuffix(".run(using: &rng) }"))
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
            callee: "normalize",
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
                    sample: { rng in (Gen<Character>.letterOrNumber.string(of: 0...8)).run(using: &rng) },
                    property: { value in normalize(normalize(value)) == normalize(value) }
                )
                if case let .failed(_, _, input, error) = result {
                    Issue.record(
                        "normalize(_:) failed idempotence at input \\(input). \\(error?.message ?? "")"
                    )
                }
            }
            """
        #expect(source == expected)
    }

    // MARK: - deterministic(...)

    private static let determinismSeed = SamplingSeed.Value(
        stateA: 0x1, stateB: 0x2, stateC: 0x3, stateD: 0x4
    )

    @Test
    func deterministicEmitsRunnableStubForSingleParam() {
        let source = LiftedTestEmitter.deterministic(
            funcName: "describe",
            parameters: [.init(label: nil, generator: "Gen<Int>.int()")],
            seed: Self.determinismSeed
        )
        #expect(source.contains("@Test func describe_isDeterministic() async {"))
        #expect(source.contains("trials: 100"))
        #expect(source.contains("sample: { rng in (Gen<Int>.int()).run(using: &rng) }"))
        #expect(source.contains("property: { value in describe(value) == describe(value) }"))
        #expect(source.contains("is not deterministic"))
    }

    @Test
    func deterministicEmitsArgumentLabelForLabeledSingleParam() {
        let source = LiftedTestEmitter.deterministic(
            funcName: "memberGenerator",
            parameters: [.init(label: "forTypeName", generator: "Gen<Character>.letterOrNumber.string(of: 0...8)")],
            seed: Self.determinismSeed
        )
        #expect(source.contains(
            "memberGenerator(forTypeName: value) == memberGenerator(forTypeName: value)"
        ))
    }

    @Test
    func deterministicUsesApproximateEqualityForFloatingPointReturn() {
        let source = LiftedTestEmitter.deterministic(
            funcName: "scale",
            parameters: [.init(label: nil, generator: "Gen<Int>.int()")],
            seed: Self.determinismSeed,
            equalityKind: .approximate
        )
        #expect(source.contains("approximatelyEqual(scale(value), scale(value))"))
    }

    @Test
    func deterministicEmitsTupleDrawForMultipleParams() {
        let source = LiftedTestEmitter.deterministic(
            funcName: "combine",
            parameters: [
                .init(label: nil, generator: "Gen<Int>.int()"),
                .init(label: "with", generator: "Gen<Character>.letterOrNumber.string(of: 0...8)")
            ],
            seed: Self.determinismSeed
        )
        // One draw per parameter, returned as a tuple.
        #expect(source.contains("let arg0 = (Gen<Int>.int()).run(using: &rng)"))
        #expect(source.contains(
            "let arg1 = (Gen<Character>.letterOrNumber.string(of: 0...8)).run(using: &rng)"
        ))
        #expect(source.contains("return (arg0, arg1)"))
        // The call applies each label positionally from the tuple.
        #expect(source.contains("combine(args.0, with: args.1) == combine(args.0, with: args.1)"))
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
            forward: "encode",
            inverse: "decode",
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
                    sample: { rng in (MyType.gen()).run(using: &rng) },
                    property: { value in decode(encode(value)) == value }
                )
                if case let .failed(_, _, input, error) = result {
                    Issue.record(
                        "encode/decode round-trip failed at input \\(input). \\(error?.message ?? "")"
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
            callee: "normalize",
            typeName: "String",
            seed: seed,
            generator: LiftedTestEmitter.defaultGenerator(for: "String")
        )
        let second = LiftedTestEmitter.idempotent(
            callee: "normalize",
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
            callee: "transform",
            typeName: "Int",
            seed: seed,
            generator: "Gen<Int>.int()"
        )
        let roundTripSource = LiftedTestEmitter.roundTrip(
            forward: "transform",
            inverse: "untransform",
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
            callee: "length",
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
                                let lhs = (Gen<Character>.letterOrNumber.string(of: 0...8)).run(using: &rng)
                                let rhs = (Gen<Character>.letterOrNumber.string(of: 0...8)).run(using: &rng)
                                return lhs < rhs ? (lhs, rhs) : (rhs, lhs)
                            },
                    property: { pair in length(pair.0) <= length(pair.1) }
                )
                if case let .failed(_, _, input, error) = result {
                    Issue.record(
                        "length(_:) failed monotonicity at input \\(input). \\(error?.message ?? "")"
                    )
                }
            }
            """
        #expect(source == expected)
    }

    // MARK: - invariantPreserving(...) byte-stable golden (M7.3)

    // The expected block is a byte-stable copy of emitted output; the keypath
    // failure message is legitimately one long line, so line_length is disabled
    // for this golden only.
    // swiftlint:disable line_length
    @Test
    func invariantPreservingEmitsByteStableTestStub() {
        let seed = SamplingSeed.Value(
            stateA: 0x1010_1010_1010_1010,
            stateB: 0x2020_2020_2020_2020,
            stateC: 0x3030_3030_3030_3030,
            stateD: 0x4040_4040_4040_4040
        )
        let source = LiftedTestEmitter.invariantPreserving(
            callee: "adjust",
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
                    sample: { rng in (Widget.gen()).run(using: &rng) },
                    property: { value in !value[keyPath: \\.isValid] || adjust(value)[keyPath: \\.isValid] }
                )
                if case let .failed(_, _, input, error) = result {
                    Issue.record(
                        "adjust(_:) failed invariant preservation \\.isValid at input \\(input). \\(error?.message ?? "")"
                    )
                }
            }
            """
        #expect(source == expected)
    }
    // swiftlint:enable line_length

    @Test
    func invariantPreservingSanitizesNestedKeypathInTestName() {
        let seed = SamplingSeed.Value(stateA: 1, stateB: 2, stateC: 3, stateD: 4)
        let source = LiftedTestEmitter.invariantPreserving(
            callee: "transfer",
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
            callee: "score",
            typeName: "Widget",
            returnType: "Int",
            seed: seed,
            generator: "Widget.gen()"
        )
        let invariantSource = LiftedTestEmitter.invariantPreserving(
            callee: "score",
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
