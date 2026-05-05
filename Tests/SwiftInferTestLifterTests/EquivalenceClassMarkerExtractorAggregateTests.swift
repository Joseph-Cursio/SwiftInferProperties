import Testing
import SwiftInferCore
@testable import SwiftInferTestLifter

@Suite("EquivalenceClassMarkerExtractor — partition aggregation (M11.1)")
struct ECMarkerExtractorAggregateTests {

    private static func parsedCorpus(
        _ sources: [(name: String, body: String)]
    ) -> ([TestMethodSummary], [SlicedTestBody]) {
        var methods: [TestMethodSummary] = []
        var slices: [SlicedTestBody] = []
        for source in sources {
            let summaries = TestSuiteParser.scan(
                source: """
                import XCTest
                final class T: XCTestCase {
                    func \(source.name)() {
                        \(source.body)
                    }
                }
                """,
                file: "\(source.name).swift"
            )
            let summary = summaries[0]
            methods.append(summary)
            slices.append(Slicer.slice(summary.body))
        }
        return (methods, slices)
    }

    @Test("Three Valid + three Invalid sites against same predicate → one PartitionCandidate")
    func aggregateHomogeneousCorpus() {
        let (methods, slices) = Self.parsedCorpus([
            (name: "testValid_a", body: "XCTAssertTrue(isValid(\"a@b\"))"),
            (name: "testValid_b", body: "XCTAssertTrue(isValid(\"x@y\"))"),
            (name: "testValid_c", body: "XCTAssertTrue(isValid(\"p@q\"))"),
            (name: "testInvalid_a", body: "XCTAssertFalse(isValid(\"abc\"))"),
            (name: "testInvalid_b", body: "XCTAssertFalse(isValid(\"\"))"),
            (name: "testInvalid_c", body: "XCTAssertFalse(isValid(\"@\"))")
        ])
        let candidates = EquivalenceClassMarkerExtractor.extract(
            methods: methods, slices: slices, markerTable: MarkerPair.defaultTable
        )
        #expect(candidates.count == 1)
        let candidate = candidates[0]
        #expect(candidate.predicateName == "isValid")
        #expect(candidate.positiveSites.count == 3)
        #expect(candidate.negativeSites.count == 3)
        #expect(candidate.outlierSiteCount == 0)
    }

    @Test("Different predicates against same marker pair → separate PartitionCandidates")
    func aggregateDifferentPredicatesProduceTwoCandidates() {
        let (methods, slices) = Self.parsedCorpus([
            (name: "testValid_emailA", body: "XCTAssertTrue(isValidEmail(\"a@b\"))"),
            (name: "testValid_emailB", body: "XCTAssertTrue(isValidEmail(\"x@y\"))"),
            (name: "testValid_emailC", body: "XCTAssertTrue(isValidEmail(\"p@q\"))"),
            (name: "testInvalid_emailA", body: "XCTAssertFalse(isValidEmail(\"abc\"))"),
            (name: "testInvalid_emailB", body: "XCTAssertFalse(isValidEmail(\"\"))"),
            (name: "testInvalid_emailC", body: "XCTAssertFalse(isValidEmail(\"@\"))"),
            (name: "testValid_phoneA", body: "XCTAssertTrue(isValidPhone(\"123\"))"),
            (name: "testValid_phoneB", body: "XCTAssertTrue(isValidPhone(\"456\"))"),
            (name: "testValid_phoneC", body: "XCTAssertTrue(isValidPhone(\"789\"))"),
            (name: "testInvalid_phoneA", body: "XCTAssertFalse(isValidPhone(\"abc\"))"),
            (name: "testInvalid_phoneB", body: "XCTAssertFalse(isValidPhone(\"\"))"),
            (name: "testInvalid_phoneC", body: "XCTAssertFalse(isValidPhone(\"!\"))")
        ])
        let candidates = EquivalenceClassMarkerExtractor.extract(
            methods: methods, slices: slices, markerTable: MarkerPair.defaultTable
        )
        #expect(candidates.count == 2)
        // Sorted alphabetically by predicateName per extractor contract
        #expect(candidates[0].predicateName == "isValidEmail")
        #expect(candidates[1].predicateName == "isValidPhone")
    }

    @Test("Polarity-mismatched site within a partition is recorded as an outlier")
    func aggregateOutlierPropagatesIntoCandidate() {
        let (methods, slices) = Self.parsedCorpus([
            (name: "testValid_a", body: "XCTAssertTrue(isValid(\"a@b\"))"),
            (name: "testValid_b", body: "XCTAssertTrue(isValid(\"x@y\"))"),
            (name: "testValid_outlier", body: "XCTAssertFalse(isValid(\"a@b\"))"),
            (name: "testInvalid_a", body: "XCTAssertFalse(isValid(\"abc\"))"),
            (name: "testInvalid_b", body: "XCTAssertFalse(isValid(\"\"))"),
            (name: "testInvalid_c", body: "XCTAssertFalse(isValid(\"@\"))")
        ])
        let candidates = EquivalenceClassMarkerExtractor.extract(
            methods: methods, slices: slices, markerTable: MarkerPair.defaultTable
        )
        #expect(candidates.count == 1)
        #expect(candidates[0].outlierSiteCount == 1)
    }

    @Test("Empty corpus → empty result")
    func aggregateEmpty() {
        let result = EquivalenceClassMarkerExtractor.extract(
            methods: [], slices: [], markerTable: MarkerPair.defaultTable
        )
        #expect(result.isEmpty)
    }

    @Test("Mismatched method/slice counts → empty result (defensive guard)")
    func aggregateMismatchedCountsGuard() {
        let (methods, _) = Self.parsedCorpus([
            (name: "testValid_x", body: "XCTAssertTrue(isValid(\"a\"))")
        ])
        let result = EquivalenceClassMarkerExtractor.extract(
            methods: methods, slices: [], markerTable: MarkerPair.defaultTable
        )
        #expect(result.isEmpty)
    }
}
