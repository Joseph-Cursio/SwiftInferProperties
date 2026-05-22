import SwiftInferCore
@testable import SwiftInferTestLifter
import Testing

@Suite("EquivalenceClassMarkerExtractor — N-class classify + aggregation (M13.2)")
struct ECMarkerExtractorNClassTests {

    private static let sizesMarkerSet = MarkerSet(
        name: "Sizes",
        markers: ["Small", "Medium", "Large"]
    )

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

    // MARK: - classifyNClass — single method/slice

    @Test("XCTAssertEqual(predicate(x), .case) matches for marker-bearing method")
    func classifyXCTAssertEqualMatched() {
        let (methods, slices) = Self.parsedCorpus([
            (name: "testSmall_a", body: "XCTAssertEqual(size(box), .small)")
        ])
        let result = EquivalenceClassMarkerExtractor.classifyNClass(
            method: methods[0], slice: slices[0], markerSet: Self.sizesMarkerSet
        )
        #expect(result == .matched(predicateName: "size", marker: "Small"))
    }

    @Test("Symmetric XCTAssertEqual(.case, predicate(x)) also matches")
    func classifyXCTAssertEqualSymmetric() {
        let (methods, slices) = Self.parsedCorpus([
            (name: "testMedium_a", body: "XCTAssertEqual(.medium, size(box))")
        ])
        let result = EquivalenceClassMarkerExtractor.classifyNClass(
            method: methods[0], slice: slices[0], markerSet: Self.sizesMarkerSet
        )
        #expect(result == .matched(predicateName: "size", marker: "Medium"))
    }

    @Test("Swift Testing #expect(predicate(x) == .case) also matches")
    func classifyExpectEqualMatched() {
        let (methods, slices) = Self.parsedCorpus([
            (name: "testLarge_a", body: "#expect(size(box) == .large)")
        ])
        let result = EquivalenceClassMarkerExtractor.classifyNClass(
            method: methods[0], slice: slices[0], markerSet: Self.sizesMarkerSet
        )
        #expect(result == .matched(predicateName: "size", marker: "Large"))
    }

    @Test("Method without any marker → no classification")
    func classifyNoMarkerReturnsNil() {
        let (methods, slices) = Self.parsedCorpus([
            (name: "testCheck_a", body: "XCTAssertEqual(size(box), .small)")
        ])
        let result = EquivalenceClassMarkerExtractor.classifyNClass(
            method: methods[0], slice: slices[0], markerSet: Self.sizesMarkerSet
        )
        #expect(result == nil)
    }

    @Test("Method with two markers → ambiguousMarker outlier")
    func classifyAmbiguousMarker() {
        let (methods, slices) = Self.parsedCorpus([
            (name: "testSmallLarge_a", body: "XCTAssertEqual(size(box), .small)")
        ])
        let result = EquivalenceClassMarkerExtractor.classifyNClass(
            method: methods[0], slice: slices[0], markerSet: Self.sizesMarkerSet
        )
        #expect(result == .outlier(predicateName: nil, reason: .ambiguousMarker))
    }

    @Test("Marker-bearing method without terminal assertion → noTerminalAssertion outlier")
    func classifyNoTerminalAssertion() {
        let (methods, slices) = Self.parsedCorpus([
            (name: "testSmall_a", body: "let x = 1")
        ])
        let result = EquivalenceClassMarkerExtractor.classifyNClass(
            method: methods[0], slice: slices[0], markerSet: Self.sizesMarkerSet
        )
        #expect(result == .outlier(predicateName: nil, reason: .noTerminalAssertion))
    }

    @Test("XCTAssertTrue assertion (not an equality) → nonEqualityAssertion outlier")
    func classifyNonEqualityAssertion() {
        let (methods, slices) = Self.parsedCorpus([
            (name: "testSmall_a", body: "XCTAssertTrue(size(box) == .small)")
        ])
        let result = EquivalenceClassMarkerExtractor.classifyNClass(
            method: methods[0], slice: slices[0], markerSet: Self.sizesMarkerSet
        )
        #expect(result == .outlier(predicateName: nil, reason: .nonEqualityAssertion))
    }

    @Test("Case literal mismatching marker name → caseLiteralMismatch outlier")
    func classifyCaseLiteralMismatch() {
        let (methods, slices) = Self.parsedCorpus([
            (name: "testSmall_a", body: "XCTAssertEqual(size(box), .medium)")
        ])
        let result = EquivalenceClassMarkerExtractor.classifyNClass(
            method: methods[0], slice: slices[0], markerSet: Self.sizesMarkerSet
        )
        #expect(result == .outlier(predicateName: "size", reason: .caseLiteralMismatch))
    }

    // MARK: - End-to-end aggregation via extract(...,markerTable: MarkerTable)

    @Test("Three-class corpus produces an N-class candidate via the MarkerTable extract overload")
    func aggregateThreeClassCorpus() {
        let (methods, slices) = Self.parsedCorpus([
            (name: "testSmall_a", body: "XCTAssertEqual(size(box), .small)"),
            (name: "testSmall_b", body: "XCTAssertEqual(size(box), .small)"),
            (name: "testSmall_c", body: "XCTAssertEqual(size(box), .small)"),
            (name: "testMedium_a", body: "XCTAssertEqual(size(box), .medium)"),
            (name: "testMedium_b", body: "XCTAssertEqual(size(box), .medium)"),
            (name: "testMedium_c", body: "XCTAssertEqual(size(box), .medium)"),
            (name: "testLarge_a", body: "XCTAssertEqual(size(box), .large)"),
            (name: "testLarge_b", body: "XCTAssertEqual(size(box), .large)"),
            (name: "testLarge_c", body: "XCTAssertEqual(size(box), .large)")
        ])
        let table = MarkerTable(pairs: [], sets: [Self.sizesMarkerSet])
        let candidates = EquivalenceClassMarkerExtractor.extract(
            methods: methods, slices: slices, markerTable: table
        )
        #expect(candidates.count == 1)
        let candidate = candidates[0]
        #expect(candidate.predicateName == "size")
        #expect(candidate.markerSet == Self.sizesMarkerSet)
        #expect(candidate.markerPair == nil)
        #expect(candidate.outlierSiteCount == 0)
        let buckets = try? #require(candidate.nClassBucketsByMarker)
        #expect(buckets?["Small"]?.count == 3)
        #expect(buckets?["Medium"]?.count == 3)
        #expect(buckets?["Large"]?.count == 3)
    }

    @Test("Polluted bucket (case-literal mismatch) records outlier and kills the candidate downstream")
    func aggregateMismatchOutlier() {
        let (methods, slices) = Self.parsedCorpus([
            (name: "testSmall_a", body: "XCTAssertEqual(size(box), .small)"),
            (name: "testSmall_b", body: "XCTAssertEqual(size(box), .small)"),
            (name: "testSmall_c", body: "XCTAssertEqual(size(box), .small)"),
            (name: "testMedium_a", body: "XCTAssertEqual(size(box), .medium)"),
            (name: "testMedium_b", body: "XCTAssertEqual(size(box), .medium)"),
            (name: "testMedium_outlier", body: "XCTAssertEqual(size(box), .small)"),
            (name: "testLarge_a", body: "XCTAssertEqual(size(box), .large)"),
            (name: "testLarge_b", body: "XCTAssertEqual(size(box), .large)"),
            (name: "testLarge_c", body: "XCTAssertEqual(size(box), .large)")
        ])
        let table = MarkerTable(pairs: [], sets: [Self.sizesMarkerSet])
        let candidates = EquivalenceClassMarkerExtractor.extract(
            methods: methods, slices: slices, markerTable: table
        )
        #expect(candidates.count == 1)
        #expect(candidates[0].outlierSiteCount == 1)
    }

    @Test("Two-class + N-class candidates can coexist for different predicates")
    func aggregateTwoClassPlusNClassCoexist() {
        let (methods, slices) = Self.parsedCorpus([
            // Two-class on isOK
            (name: "testValid_a", body: "XCTAssertTrue(isOK(\"a\"))"),
            (name: "testValid_b", body: "XCTAssertTrue(isOK(\"b\"))"),
            (name: "testValid_c", body: "XCTAssertTrue(isOK(\"c\"))"),
            (name: "testInvalid_a", body: "XCTAssertFalse(isOK(\"x\"))"),
            (name: "testInvalid_b", body: "XCTAssertFalse(isOK(\"y\"))"),
            (name: "testInvalid_c", body: "XCTAssertFalse(isOK(\"z\"))"),
            // N-class on size
            (name: "testSmall_a", body: "XCTAssertEqual(size(box), .small)"),
            (name: "testSmall_b", body: "XCTAssertEqual(size(box), .small)"),
            (name: "testSmall_c", body: "XCTAssertEqual(size(box), .small)"),
            (name: "testMedium_a", body: "XCTAssertEqual(size(box), .medium)"),
            (name: "testMedium_b", body: "XCTAssertEqual(size(box), .medium)"),
            (name: "testMedium_c", body: "XCTAssertEqual(size(box), .medium)"),
            (name: "testLarge_a", body: "XCTAssertEqual(size(box), .large)"),
            (name: "testLarge_b", body: "XCTAssertEqual(size(box), .large)"),
            (name: "testLarge_c", body: "XCTAssertEqual(size(box), .large)")
        ])
        let table = MarkerTable(
            pairs: [MarkerPair(positive: "Valid", negative: "Invalid")],
            sets: [Self.sizesMarkerSet]
        )
        let candidates = EquivalenceClassMarkerExtractor.extract(
            methods: methods, slices: slices, markerTable: table
        )
        #expect(candidates.count == 2)
        // Sort: predicateName ascending. "isOK" < "size".
        #expect(candidates[0].predicateName == "isOK")
        #expect(candidates[0].markerPair == MarkerPair(positive: "Valid", negative: "Invalid"))
        #expect(candidates[1].predicateName == "size")
        #expect(candidates[1].markerSet == Self.sizesMarkerSet)
    }

    // MARK: - Mixed-predicate kill (different predicates → different keys)

    @Test("Different predicates under same marker set produce separate candidates")
    func mixedPredicatesProduceSeparateCandidates() {
        let (methods, slices) = Self.parsedCorpus([
            (name: "testSmall_a", body: "XCTAssertEqual(sizeA(box), .small)"),
            (name: "testSmall_b", body: "XCTAssertEqual(sizeA(box), .small)"),
            (name: "testSmall_c", body: "XCTAssertEqual(sizeA(box), .small)"),
            (name: "testMedium_a", body: "XCTAssertEqual(sizeB(box), .medium)"),
            (name: "testMedium_b", body: "XCTAssertEqual(sizeB(box), .medium)"),
            (name: "testMedium_c", body: "XCTAssertEqual(sizeB(box), .medium)"),
            (name: "testLarge_a", body: "XCTAssertEqual(sizeA(box), .large)"),
            (name: "testLarge_b", body: "XCTAssertEqual(sizeA(box), .large)"),
            (name: "testLarge_c", body: "XCTAssertEqual(sizeA(box), .large)")
        ])
        let table = MarkerTable(pairs: [], sets: [Self.sizesMarkerSet])
        let candidates = EquivalenceClassMarkerExtractor.extract(
            methods: methods, slices: slices, markerTable: table
        )
        // sizeA has Small + Large = 2 active buckets; sizeB has Medium = 1.
        // Both candidates emerge from the extractor; the M13.2 detector
        // would reject both downstream (< 3 active buckets each).
        #expect(candidates.count == 2)
        #expect(candidates.contains { $0.predicateName == "sizeA" })
        #expect(candidates.contains { $0.predicateName == "sizeB" })
    }
}
