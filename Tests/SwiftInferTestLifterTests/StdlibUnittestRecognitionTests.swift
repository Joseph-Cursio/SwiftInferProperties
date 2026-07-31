@testable import SwiftInferTestLifter
import Testing

/// `StdlibUnittest` recognition — the swift.org stdlib harness.
///
/// Measured at `swift` @ `408632e5` over `test/stdlib` +
/// `validation-test/stdlib` (558 files): **4,171 tests recognized where the
/// lifter previously saw 0**, of which 2,263 slice to an assertion anchor.
@Suite("TestSuiteParser — StdlibUnittest test closures")
struct StdlibUnittestRecognitionTests {

    // MARK: - The two call shapes

    @Test("direct trailing-closure form is recognized")
    func directForm() throws {
        let source = """
        var SetTestSuite = TestSuite("Set")
        SetTestSuite.test("Set.subtracting") {
            expectEqual(a.subtracting(b), c)
        }
        """
        let summaries = TestSuiteParser.scan(source: source, file: "Set.swift")
        #expect(summaries.count == 1)
        let summary = try #require(summaries.first)
        #expect(summary.harness == .stdlibUnittest)
        #expect(summary.className == "SetTestSuite")
        #expect(summary.methodName == "Set.subtracting")
    }

    /// The chained form is why recognition cannot key on the trailing
    /// closure's immediate callee: here that callee is `.code`, and the
    /// `.test("…")` call is two links down the base chain.
    @Test("chained .xfail(…).code { } form is recognized")
    func chainedCodeForm() throws {
        let source = """
        StringTests.test("Comparable")
          .xfail(.always)
          .code {
            expectEqual(x, y)
        }
        """
        let summaries = TestSuiteParser.scan(source: source, file: "StringAPI.swift")
        #expect(summaries.count == 1)
        let summary = try #require(summaries.first)
        #expect(summary.harness == .stdlibUnittest)
        #expect(summary.className == "StringTests")
        #expect(summary.methodName == "Comparable")
    }

    /// The corpus spells the receiver `suite`, `tests`, `SetTestSuite`,
    /// `mirrors`, `FloatingPoint`, … with no common prefix, so the rule is
    /// structural rather than name-based.
    @Test("receiver name is not part of the rule")
    func receiverNameIsIrrelevant() {
        for receiver in ["suite", "tests", "mirrors", "FloatingPoint", "OptionSetTests"] {
            let source = "\(receiver).test(\"case\") { expectEqual(1, 1) }"
            let summaries = TestSuiteParser.scan(source: source, file: "T.swift")
            #expect(summaries.count == 1, "\(receiver) should be recognized")
            #expect(summaries.first?.className == receiver)
        }
    }

    /// Interpolated labels are common in the corpus
    /// (`"Comparable: line \\(test.loc.line)"`). The label is a human-facing
    /// name rather than anything the lifter reasons over, so the interpolation
    /// is kept verbatim — including its `\\(…)` delimiters, which makes it
    /// obvious in output that the segment was not a constant.
    @Test("interpolated label keeps its source spelling verbatim")
    func interpolatedLabel() {
        let source = #"""
        StringTests.test("Comparable: line \(test.loc.line)") { expectEqual(1, 1) }
        """#
        let summaries = TestSuiteParser.scan(source: source, file: "T.swift")
        #expect(summaries.first?.methodName == #"Comparable: line \(test.loc.line)"#)
    }

    // MARK: - What the rule deliberately does not match

    /// The string-literal first argument is what separates a test declaration
    /// from an arbitrary `.test { }` predicate-style call.
    @Test("a non-string-literal first argument is not a test")
    func nonLiteralFirstArgumentIsNotATest() {
        let source = """
        collection.test(somePredicate) { element in
            expectEqual(element, element)
        }
        """
        #expect(TestSuiteParser.scan(source: source, file: "T.swift").isEmpty)
    }

    @Test("a call with no trailing closure is not a test")
    func noTrailingClosureIsNotATest() {
        // `StaticBigInt.swift` writes this shape — the body lives in a separate
        // method, so there is nothing inline to slice.
        let source = """
        testSuite.test("BinaryRepresentation", testCase.testBinaryRepresentation)
        """
        #expect(TestSuiteParser.scan(source: source, file: "StaticBigInt.swift").isEmpty)
    }

    /// A documented limit, not an oversight: function bodies are never
    /// descended into (the M1.1 nested-decl contract), so a `.test(…) { }`
    /// written inside a `func` is missed. Witness in the corpus:
    /// `test/stdlib/Observation/Observable.swift` puts 20 of them inside
    /// `static func main() async`.
    @Test("a test closure inside a func body is NOT recognized (known limit)")
    func testInsideFunctionBodyIsMissed() {
        let source = """
        enum Runner {
            static func main() async {
                let suite = TestSuite("Observable")
                suite.test("only instantiate") {
                    expectEqual(1, 1)
                }
            }
        }
        """
        #expect(TestSuiteParser.scan(source: source, file: "Observable.swift").isEmpty)
    }

    // MARK: - The body reaches the slicer

    /// Recognition is only worth anything if the body slices. This is the
    /// end-to-end claim the whole change rests on.
    @Test("the recognized body slices to an expectEqual anchor")
    func bodySlicesToAnAssertion() throws {
        let source = """
        ArrayTestSuite.test("sort/idempotent") {
            let sorted = input.sorted()
            expectEqual(sorted.sorted(), sorted)
        }
        """
        let summary = try #require(TestSuiteParser.scan(source: source, file: "Array.swift").first)
        let sliced = Slicer.slice(summary.body)
        let assertion = try #require(sliced.assertion)
        #expect(assertion.kind == .xctAssertEqual)
        #expect(assertion.arguments.count == 2)
    }

    @Test("multiple test closures in one file each emit a summary")
    func multipleClosures() {
        let source = """
        var suite = TestSuite("S")
        suite.test("one") { expectEqual(1, 1) }
        suite.test("two") { expectTrue(flag) }
        suite.test("three") { expectFalse(flag) }
        """
        let summaries = TestSuiteParser.scan(source: source, file: "T.swift")
        #expect(summaries.count == 3)
        #expect(summaries.map(\.methodName) == ["one", "two", "three"])
    }
}
