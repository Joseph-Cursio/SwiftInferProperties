import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("LiftedTestEmitter — M5.5 lifted-only arms (countInvariance, reduceEquivalence)")
struct LiftedTestEmitterM5Tests {

    private static let goldenSeed = SamplingSeed.Value(
        stateA: 0x0123456789ABCDEF,
        stateB: 0xFEDCBA9876543210,
        stateC: 0x1111111111111111,
        stateD: 0x2222222222222222
    )

    // MARK: - liftedCountInvariance(...) byte-stable golden

    @Test
    func liftedCountInvarianceEmitsByteStableTestStub() {
        let source = LiftedTestEmitter.liftedCountInvariance(
            funcName: "filter",
            typeName: "Int",
            seed: Self.goldenSeed,
            generator: "Gen<Int>.int()"
        )
        let expected = """

            @Test func filter_preservesCount() async {
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
                    sample: { rng in ((Gen<Int>.int()).array(of: 0...20)).run(&rng) },
                    property: { xs in filter(xs).count == xs.count }
                )
                if case let .failed(_, _, input, error) = result {
                    Issue.record(
                        "filter(_:) failed count-invariance at input \\(input)."
                            + " \\(error?.message ?? \\"\\")"
                    )
                }
            }
            """
        #expect(source == expected)
    }

    @Test
    func liftedCountInvarianceWithCustomGeneratorTypeUsesUserGenFallback() {
        let source = LiftedTestEmitter.liftedCountInvariance(
            funcName: "transform",
            typeName: "Item",
            seed: Self.goldenSeed,
            generator: "Item.gen()"
        )
        // Verify the sample expression interpolates the user's `Item.gen()`
        // through the kit's `.array(of: 0...20)` combinator without
        // post-processing.
        #expect(source.contains("(Item.gen()).array(of: 0...20)"))
        #expect(source.contains("transform(xs).count == xs.count"))
    }

    // MARK: - liftedReduceEquivalence(...) byte-stable golden

    @Test
    func liftedReduceEquivalenceWithOperatorOpEmitsByteStableTestStub() {
        let source = LiftedTestEmitter.liftedReduceEquivalence(
            opName: "+",
            elementTypeName: "Int",
            seedSource: "0",
            seed: Self.goldenSeed,
            generator: "Gen<Int>.int()"
        )
        let expected = """

            @Test func op_plus_reduceIsReversalInvariant() async {
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
                    sample: { rng in ((Gen<Int>.int()).array(of: 0...20)).run(&rng) },
                    property: { xs in xs.reduce(0, +) == xs.reversed().reduce(0, +) }
                )
                if case let .failed(_, _, input, error) = result {
                    Issue.record(
                        "+ reduce/.reversed().reduce equivalence failed at input \\(input)."
                            + " \\(error?.message ?? \\"\\")"
                    )
                }
            }
            """
        #expect(source == expected)
    }

    @Test
    func liftedReduceEquivalenceWithNamedFunctionOpUsesIdentifierAsTestName() {
        let source = LiftedTestEmitter.liftedReduceEquivalence(
            opName: "combine",
            elementTypeName: "Money",
            seedSource: ".zero",
            seed: Self.goldenSeed,
            generator: "Money.gen()"
        )
        // Bare-identifier op passes through the sanitizer unchanged.
        #expect(source.contains("@Test func combine_reduceIsReversalInvariant() async"))
        #expect(source.contains("xs.reduce(.zero, combine)"))
        #expect(source.contains("xs.reversed().reduce(.zero, combine)"))
    }

    @Test
    func liftedReduceEquivalenceMapsCommonOperatorsToReadableTestNames() {
        let pairs: [(op: String, expectedFragment: String)] = [
            ("+", "op_plus_reduceIsReversalInvariant"),
            ("-", "op_minus_reduceIsReversalInvariant"),
            ("*", "op_times_reduceIsReversalInvariant"),
            ("/", "op_divide_reduceIsReversalInvariant"),
            ("%", "op_modulo_reduceIsReversalInvariant"),
            ("&&", "op_and_reduceIsReversalInvariant"),
            ("||", "op_or_reduceIsReversalInvariant")
        ]
        for pair in pairs {
            let source = LiftedTestEmitter.liftedReduceEquivalence(
                opName: pair.op,
                elementTypeName: "Int",
                seedSource: "0",
                seed: Self.goldenSeed,
                generator: "Gen<Int>.int()"
            )
            #expect(source.contains("@Test func \(pair.expectedFragment)() async"))
        }
    }
}
