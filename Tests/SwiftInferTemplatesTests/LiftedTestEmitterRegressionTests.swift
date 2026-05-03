import Testing
@testable import SwiftInferTemplates

/// TestLifter M8.0 acceptance — `LiftedTestEmitter+Regression`'s 10
/// regression arms emit byte-stable single-trial test stubs over a
/// user-supplied counterexample. Each arm parallels the corresponding
/// non-regression sibling but drops the backend / seed / sample /
/// `forAll` machinery — pure deterministic `let value: T = <input>;
/// #expect(<property>)`.
@Suite("LiftedTestEmitter — regression stubs (M8.0)")
struct LiftedTestEmitterRegressionTests {

    @Test
    func regressionFileHashIsStableAndShort() {
        let hash1 = LiftedTestEmitter.regressionFileHash(for: "\"hello\\n\"")
        let hash2 = LiftedTestEmitter.regressionFileHash(for: "\"hello\\n\"")
        let hash3 = LiftedTestEmitter.regressionFileHash(for: "\"goodbye\"")
        #expect(hash1 == hash2)
        #expect(hash1 != hash3)
        #expect(hash1.count == 8)
        let allHex = hash1.allSatisfy { $0.isHexDigit }
        #expect(allHex)
    }

    @Test
    func idempotentRegressionEmitsByteStableStub() {
        let source = LiftedTestEmitter.idempotentRegression(
            funcName: "normalize",
            typeName: "String",
            inputSource: "\"hello\\n\""
        )
        let hash = LiftedTestEmitter.regressionFileHash(for: "\"hello\\n\"")
        let expected = """

            @Test func normalize_isIdempotent_regression_\(hash)() {
                let value: String = "hello\\n"
                #expect(normalize(normalize(value)) == normalize(value))
            }
            """
        #expect(source == expected)
    }

    @Test
    func roundTripRegressionEmitsByteStableStub() {
        let source = LiftedTestEmitter.roundTripRegression(
            forwardName: "encode",
            inverseName: "decode",
            typeName: "Int",
            inputSource: "42"
        )
        let hash = LiftedTestEmitter.regressionFileHash(for: "42")
        let expected = """

            @Test func encode_decode_roundTrip_regression_\(hash)() {
                let value: Int = 42
                #expect(decode(encode(value)) == value)
            }
            """
        #expect(source == expected)
    }

    @Test
    func monotonicRegressionEmitsByteStableStubWithTuplePair() {
        let source = LiftedTestEmitter.monotonicRegression(
            funcName: "applyDiscount",
            tupleType: "(Int, Int)",
            inputSource: "(2, 3)"
        )
        #expect(source.contains("@Test func applyDiscount_isMonotonic_regression_"))
        #expect(source.contains("let pair: (Int, Int) = (2, 3)"))
        #expect(source.contains("#expect(applyDiscount(pair.0) <= applyDiscount(pair.1))"))
    }

    @Test
    func commutativeRegressionEmitsByteStableStubWithTuplePair() {
        let source = LiftedTestEmitter.commutativeRegression(
            funcName: "merge",
            tupleType: "([Int], [Int])",
            inputSource: "([1, 2], [3, 4])"
        )
        #expect(source.contains("@Test func merge_isCommutative_regression_"))
        #expect(source.contains("let pair: ([Int], [Int]) = ([1, 2], [3, 4])"))
        #expect(source.contains("#expect(merge(pair.0, pair.1) == merge(pair.1, pair.0))"))
    }

    @Test
    func associativeRegressionEmitsByteStableStubWithTriple() {
        let source = LiftedTestEmitter.associativeRegression(
            funcName: "combine",
            tripleType: "(Int, Int, Int)",
            inputSource: "(1, 2, 3)"
        )
        #expect(source.contains("@Test func combine_isAssociative_regression_"))
        #expect(source.contains("let triple: (Int, Int, Int) = (1, 2, 3)"))
        #expect(source.contains("combine(combine(triple.0, triple.1), triple.2)"))
        #expect(source.contains("== combine(triple.0, combine(triple.1, triple.2))"))
    }

    @Test
    func identityElementRegressionEmitsByteStableStub() {
        let source = LiftedTestEmitter.identityElementRegression(
            funcName: "union",
            typeName: "IntSet",
            identityName: "empty",
            inputSource: "IntSet([1, 2, 3])"
        )
        #expect(source.contains("@Test func union_hasIdentity_empty_regression_"))
        #expect(source.contains("let value: IntSet = IntSet([1, 2, 3])"))
        #expect(source.contains("union(value, IntSet.empty) == value"))
        #expect(source.contains("union(IntSet.empty, value) == value"))
    }

    @Test
    func inversePairRegressionEmitsByteStableStub() {
        let source = LiftedTestEmitter.inversePairRegression(
            forwardName: "negate",
            inverseName: "negate",
            typeName: "Int",
            inputSource: "-5"
        )
        #expect(source.contains("@Test func negate_negate_inversePair_regression_"))
        #expect(source.contains("let value: Int = -5"))
        #expect(source.contains("#expect(negate(negate(value)) == value)"))
    }

    @Test
    func invariantPreservingRegressionEmitsByteStableStub() {
        let source = LiftedTestEmitter.invariantPreservingRegression(
            funcName: "adjust",
            typeName: "Widget",
            invariantName: "\\.isValid",
            inputSource: "Widget(isValid: true)"
        )
        #expect(source.contains("@Test func adjust_preservesInvariant_isValid_regression_"))
        #expect(source.contains("let value: Widget = Widget(isValid: true)"))
        #expect(source.contains("!value[keyPath: \\.isValid]"))
        #expect(source.contains("|| adjust(value)[keyPath: \\.isValid]"))
    }

    @Test
    func liftedCountInvarianceRegressionEmitsByteStableStub() {
        let source = LiftedTestEmitter.liftedCountInvarianceRegression(
            funcName: "filter",
            elementTypeName: "Int",
            inputSource: "[1, 2, 3, -1]"
        )
        #expect(source.contains("@Test func filter_preservesCount_regression_"))
        #expect(source.contains("let xs: [Int] = [1, 2, 3, -1]"))
        #expect(source.contains("#expect(filter(xs).count == xs.count)"))
    }

    @Test
    func liftedReduceEquivalenceRegressionEmitsByteStableStub() {
        let source = LiftedTestEmitter.liftedReduceEquivalenceRegression(
            opName: "+",
            elementTypeName: "Int",
            seedSource: "0",
            inputSource: "[1, 2, 3]"
        )
        #expect(source.contains("@Test func op_plus_reduceIsReversalInvariant_regression_"))
        #expect(source.contains("let xs: [Int] = [1, 2, 3]"))
        #expect(source.contains("xs.reduce(0, +) == xs.reversed().reduce(0, +)"))
    }

    @Test
    func reduceEquivalenceRegressionWithNamedOpUsesIdentifierAsSuffix() {
        let source = LiftedTestEmitter.liftedReduceEquivalenceRegression(
            opName: "combine",
            elementTypeName: "Money",
            seedSource: ".zero",
            inputSource: "[Money(100), Money(200)]"
        )
        #expect(source.contains("@Test func combine_reduceIsReversalInvariant_regression_"))
        #expect(source.contains("xs.reduce(.zero, combine)"))
        #expect(source.contains("xs.reversed().reduce(.zero, combine)"))
    }

    @Test
    func sameInputProducesSameHashAcrossArms() {
        // The hash is purely a function of inputSource — same input
        // → same hash regardless of which template is being
        // regressed. The test-function name still differs (it
        // includes the template + callee), but the hash suffix is
        // stable.
        let input = "\"hello\""
        let idempotent = LiftedTestEmitter.idempotentRegression(
            funcName: "f",
            typeName: "String",
            inputSource: input
        )
        let invariant = LiftedTestEmitter.invariantPreservingRegression(
            funcName: "f",
            typeName: "String",
            invariantName: "\\.isEmpty",
            inputSource: input
        )
        let hash = LiftedTestEmitter.regressionFileHash(for: input)
        #expect(idempotent.contains("regression_\(hash)("))
        #expect(invariant.contains("regression_\(hash)("))
    }
}
