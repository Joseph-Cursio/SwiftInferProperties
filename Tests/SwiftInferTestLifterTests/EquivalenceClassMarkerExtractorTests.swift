import Testing
import SwiftInferCore
@testable import SwiftInferTestLifter

@Suite("EquivalenceClassMarkerExtractor — token boundaries + classification (M11.1)")
struct EquivalenceClassMarkerExtractorTests {

    // MARK: - Tokenize (token-boundary algorithm per M11 plan OD #7)

    @Test("camelCase boundaries split words at uppercase-after-lowercase")
    func tokenizeCamelCase() {
        #expect(EquivalenceClassMarkerExtractor.tokenize("testIsValidWithPlus")
                == ["test", "Is", "Valid", "With", "Plus"])
    }

    @Test("snake_case boundaries split words at underscore")
    func tokenizeSnakeCase() {
        #expect(EquivalenceClassMarkerExtractor.tokenize("testValid_simple")
                == ["test", "Valid", "simple"])
    }

    @Test("Mixed camelCase + snake_case splits at both boundary kinds")
    func tokenizeMixed() {
        #expect(EquivalenceClassMarkerExtractor.tokenize("testEmail_validInput")
                == ["test", "Email", "valid", "Input"])
    }

    @Test("Validate is NOT split into Valid + ate — token continues into ate")
    func tokenizeValidateRetainsToken() {
        let tokens = EquivalenceClassMarkerExtractor.tokenize("testValidate_simple")
        #expect(tokens == ["test", "Validate", "simple"])
        #expect(!tokens.contains("Valid"))
    }

    @Test("Empty identifier yields empty token list")
    func tokenizeEmpty() {
        #expect(EquivalenceClassMarkerExtractor.tokenize("").isEmpty)
    }

    @Test("Trailing underscore doesn't yield an empty token")
    func tokenizeTrailingUnderscore() {
        #expect(EquivalenceClassMarkerExtractor.tokenize("testValid_") == ["test", "Valid"])
    }

    // MARK: - Classify (per (method, slice) pair against ONE marker pair)

    private static let validInvalidPair = MarkerPair(positive: "Valid", negative: "Invalid")

    private static func summaryAndSlice(name: String, body: String) -> (TestMethodSummary, SlicedTestBody) {
        let summaries = TestSuiteParser.scan(
            source: """
            import XCTest
            final class T: XCTestCase {
                func \(name)() {
                    \(body)
                }
            }
            """,
            file: "T.swift"
        )
        let summary = summaries[0]
        return (summary, Slicer.slice(summary.body))
    }

    @Test("Positive marker + asserted-true predicate call → matched .positive")
    func classifyPositiveMatch() {
        let (method, slice) = Self.summaryAndSlice(
            name: "testValid_simple",
            body: "XCTAssertTrue(isValid(\"a@b\"))"
        )
        let result = EquivalenceClassMarkerExtractor.classify(
            method: method, slice: slice, markerPair: Self.validInvalidPair
        )
        #expect(result == .matched(predicateName: "isValid", polarity: .positive))
    }

    @Test("Negative marker + XCTAssertFalse predicate call → matched .negative")
    func classifyNegativeMatch() {
        let (method, slice) = Self.summaryAndSlice(
            name: "testInvalid_noAt",
            body: "XCTAssertFalse(isValid(\"abc\"))"
        )
        let result = EquivalenceClassMarkerExtractor.classify(
            method: method, slice: slice, markerPair: Self.validInvalidPair
        )
        #expect(result == .matched(predicateName: "isValid", polarity: .negative))
    }

    @Test("Negative marker + XCTAssert(!predicate(x)) → matched .negative via negation")
    func classifyNegativeViaNegatedXCTAssert() {
        let (method, slice) = Self.summaryAndSlice(
            name: "testInvalid_noAt",
            body: "XCTAssert(!isValid(\"abc\"))"
        )
        let result = EquivalenceClassMarkerExtractor.classify(
            method: method, slice: slice, markerPair: Self.validInvalidPair
        )
        #expect(result == .matched(predicateName: "isValid", polarity: .negative))
    }

    @Test("Positive marker + XCTAssertFalse → polarityMismatch outlier carrying predicate name")
    func classifyPolarityMismatch() {
        let (method, slice) = Self.summaryAndSlice(
            name: "testValid_unexpected",
            body: "XCTAssertFalse(isValid(\"a@b\"))"
        )
        let result = EquivalenceClassMarkerExtractor.classify(
            method: method, slice: slice, markerPair: Self.validInvalidPair
        )
        #expect(result == .outlier(predicateName: "isValid", reason: .polarityMismatch))
    }

    @Test("Method name with NO marker → returns nil (not classified)")
    func classifyNoMarkerReturnsNil() {
        let (method, slice) = Self.summaryAndSlice(
            name: "testEmail_simple",
            body: "XCTAssertTrue(isValid(\"a@b\"))"
        )
        let result = EquivalenceClassMarkerExtractor.classify(
            method: method, slice: slice, markerPair: Self.validInvalidPair
        )
        #expect(result == nil)
    }

    @Test("Validate substring does NOT trigger Valid marker (token boundary holds)")
    func classifyValidateSubstringDoesNotMatch() {
        let (method, slice) = Self.summaryAndSlice(
            name: "testValidate_simple",
            body: "XCTAssertTrue(isValid(\"a@b\"))"
        )
        let result = EquivalenceClassMarkerExtractor.classify(
            method: method, slice: slice, markerPair: Self.validInvalidPair
        )
        #expect(result == nil)
    }

    @Test("Method carrying BOTH markers → ambiguousMarker outlier with no routing predicate")
    func classifyBothMarkersAmbiguous() {
        let (method, slice) = Self.summaryAndSlice(
            name: "testValid_Invalid_mixed",
            body: "XCTAssertTrue(isValid(\"a@b\"))"
        )
        let result = EquivalenceClassMarkerExtractor.classify(
            method: method, slice: slice, markerPair: Self.validInvalidPair
        )
        #expect(result == .outlier(predicateName: nil, reason: .ambiguousMarker))
    }

    @Test("Marker present but assertion is XCTAssertEqual → nonPredicateAssertion outlier")
    func classifyNonPredicateAssertion() {
        let (method, slice) = Self.summaryAndSlice(
            name: "testValid_compare",
            body: "XCTAssertEqual(1, 1)"
        )
        let result = EquivalenceClassMarkerExtractor.classify(
            method: method, slice: slice, markerPair: Self.validInvalidPair
        )
        #expect(result == .outlier(predicateName: nil, reason: .nonPredicateAssertion))
    }

    @Test("Marker present but assertion arg is multi-arg call → nonPredicateAssertion outlier")
    func classifyMultiArgRejected() {
        let (method, slice) = Self.summaryAndSlice(
            name: "testValid_pair",
            body: "XCTAssertTrue(matches(\"a\", \"b\"))"
        )
        let result = EquivalenceClassMarkerExtractor.classify(
            method: method, slice: slice, markerPair: Self.validInvalidPair
        )
        #expect(result == .outlier(predicateName: nil, reason: .nonPredicateAssertion))
    }

    @Test("Marker present but body has no assertion → noTerminalAssertion outlier")
    func classifyNoAssertion() {
        let (method, slice) = Self.summaryAndSlice(
            name: "testValid_silentSetupOnly",
            body: "let x = 1"
        )
        let result = EquivalenceClassMarkerExtractor.classify(
            method: method, slice: slice, markerPair: Self.validInvalidPair
        )
        #expect(result == .outlier(predicateName: nil, reason: .noTerminalAssertion))
    }

    @Test("#expect(predicate(x)) recognized as positive polarity")
    func classifySwiftTestingExpectPositive() {
        let summaries = TestSuiteParser.scan(
            source: """
            import Testing
            struct T {
                @Test func testValid_simple() {
                    #expect(isValid("a@b"))
                }
            }
            """,
            file: "T.swift"
        )
        let method = summaries[0]
        let slice = Slicer.slice(method.body)
        let result = EquivalenceClassMarkerExtractor.classify(
            method: method, slice: slice, markerPair: Self.validInvalidPair
        )
        #expect(result == .matched(predicateName: "isValid", polarity: .positive))
    }

}
