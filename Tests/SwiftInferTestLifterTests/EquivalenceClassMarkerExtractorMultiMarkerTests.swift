import SwiftInferCore
@testable import SwiftInferTestLifter
import Testing

@Suite("EquivalenceClassMarkerExtractor — multi-marker scan + per-predicate ranking (M13.1)")
struct ECMarkerExtractorMultiMarkerTests {

    // MARK: - Fixture builder (mirrors ECMarkerExtractorAggregateTests)

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

    // MARK: - Curated default coverage (axis 1)

    @Test("Success/Failure corpus produces a candidate matching M11's two-class shape")
    func successFailureCorpusEmitsCandidate() {
        let (methods, slices) = Self.parsedCorpus([
            (name: "testSuccess_a", body: "XCTAssertTrue(isOK(\"a\"))"),
            (name: "testSuccess_b", body: "XCTAssertTrue(isOK(\"b\"))"),
            (name: "testSuccess_c", body: "XCTAssertTrue(isOK(\"c\"))"),
            (name: "testFailure_a", body: "XCTAssertFalse(isOK(\"x\"))"),
            (name: "testFailure_b", body: "XCTAssertFalse(isOK(\"y\"))"),
            (name: "testFailure_c", body: "XCTAssertFalse(isOK(\"z\"))")
        ])
        let candidates = EquivalenceClassMarkerExtractor.extract(
            methods: methods, slices: slices, markerTable: MarkerTable.curatedPairs
        )
        #expect(candidates.count == 1)
        let candidate = candidates[0]
        #expect(candidate.predicateName == "isOK")
        #expect(candidate.markerPair == MarkerPair(positive: "Success", negative: "Failure"))
        #expect(candidate.markerSet == nil)
        #expect(candidate.positiveSites.count == 3)
        #expect(candidate.negativeSites.count == 3)
        #expect(candidate.outlierSiteCount == 0)
    }

    @Test("Each curated pair fires for its own marker — five predicates, five candidates")
    func curatedPairsEachFire() {
        let (methods, slices) = Self.parsedCorpus([
            // Valid/Invalid → checkA
            (name: "testValid_a", body: "XCTAssertTrue(checkA(\"a\"))"),
            (name: "testValid_b", body: "XCTAssertTrue(checkA(\"b\"))"),
            (name: "testValid_c", body: "XCTAssertTrue(checkA(\"c\"))"),
            (name: "testInvalid_a", body: "XCTAssertFalse(checkA(\"x\"))"),
            (name: "testInvalid_b", body: "XCTAssertFalse(checkA(\"y\"))"),
            (name: "testInvalid_c", body: "XCTAssertFalse(checkA(\"z\"))"),
            // Success/Failure → checkB
            (name: "testSuccess_a", body: "XCTAssertTrue(checkB(\"a\"))"),
            (name: "testSuccess_b", body: "XCTAssertTrue(checkB(\"b\"))"),
            (name: "testSuccess_c", body: "XCTAssertTrue(checkB(\"c\"))"),
            (name: "testFailure_a", body: "XCTAssertFalse(checkB(\"x\"))"),
            (name: "testFailure_b", body: "XCTAssertFalse(checkB(\"y\"))"),
            (name: "testFailure_c", body: "XCTAssertFalse(checkB(\"z\"))"),
            // Accept/Reject → checkC
            (name: "testAccept_a", body: "XCTAssertTrue(checkC(\"a\"))"),
            (name: "testAccept_b", body: "XCTAssertTrue(checkC(\"b\"))"),
            (name: "testAccept_c", body: "XCTAssertTrue(checkC(\"c\"))"),
            (name: "testReject_a", body: "XCTAssertFalse(checkC(\"x\"))"),
            (name: "testReject_b", body: "XCTAssertFalse(checkC(\"y\"))"),
            (name: "testReject_c", body: "XCTAssertFalse(checkC(\"z\"))"),
            // Pass/Fail → checkD
            (name: "testPass_a", body: "XCTAssertTrue(checkD(\"a\"))"),
            (name: "testPass_b", body: "XCTAssertTrue(checkD(\"b\"))"),
            (name: "testPass_c", body: "XCTAssertTrue(checkD(\"c\"))"),
            (name: "testFail_a", body: "XCTAssertFalse(checkD(\"x\"))"),
            (name: "testFail_b", body: "XCTAssertFalse(checkD(\"y\"))"),
            (name: "testFail_c", body: "XCTAssertFalse(checkD(\"z\"))"),
            // Allowed/Forbidden → checkE
            (name: "testAllowed_a", body: "XCTAssertTrue(checkE(\"a\"))"),
            (name: "testAllowed_b", body: "XCTAssertTrue(checkE(\"b\"))"),
            (name: "testAllowed_c", body: "XCTAssertTrue(checkE(\"c\"))"),
            (name: "testForbidden_a", body: "XCTAssertFalse(checkE(\"x\"))"),
            (name: "testForbidden_b", body: "XCTAssertFalse(checkE(\"y\"))"),
            (name: "testForbidden_c", body: "XCTAssertFalse(checkE(\"z\"))")
        ])
        let candidates = EquivalenceClassMarkerExtractor.extract(
            methods: methods, slices: slices, markerTable: MarkerTable.curatedPairs
        )
        #expect(candidates.count == 5)
        let entries: [(String, MarkerPair)] = candidates.compactMap { candidate in
            guard let pair = candidate.markerPair else { return nil }
            return (candidate.predicateName, pair)
        }
        let pairsByPredicate = Dictionary(uniqueKeysWithValues: entries)
        #expect(pairsByPredicate["checkA"] == MarkerPair(positive: "Valid", negative: "Invalid"))
        #expect(pairsByPredicate["checkB"] == MarkerPair(positive: "Success", negative: "Failure"))
        #expect(pairsByPredicate["checkC"] == MarkerPair(positive: "Accept", negative: "Reject"))
        #expect(pairsByPredicate["checkD"] == MarkerPair(positive: "Pass", negative: "Fail"))
        #expect(pairsByPredicate["checkE"] == MarkerPair(positive: "Allowed", negative: "Forbidden"))
    }

    // MARK: - Per-predicate ranking (M11 OD #8)

    @Test("Same predicate fires under two pairs — winner is the higher-site-count pair")
    func multiPairFireRankingByCount() {
        let (methods, slices) = Self.parsedCorpus([
            // Valid/Invalid bucket: 3 + 3 = 6 sites for isOK
            (name: "testValid_a", body: "XCTAssertTrue(isOK(\"a\"))"),
            (name: "testValid_b", body: "XCTAssertTrue(isOK(\"b\"))"),
            (name: "testValid_c", body: "XCTAssertTrue(isOK(\"c\"))"),
            (name: "testInvalid_a", body: "XCTAssertFalse(isOK(\"x\"))"),
            (name: "testInvalid_b", body: "XCTAssertFalse(isOK(\"y\"))"),
            (name: "testInvalid_c", body: "XCTAssertFalse(isOK(\"z\"))"),
            // Success/Failure bucket: 4 + 4 = 8 sites for the same predicate
            (name: "testSuccess_a", body: "XCTAssertTrue(isOK(\"p\"))"),
            (name: "testSuccess_b", body: "XCTAssertTrue(isOK(\"q\"))"),
            (name: "testSuccess_c", body: "XCTAssertTrue(isOK(\"r\"))"),
            (name: "testSuccess_d", body: "XCTAssertTrue(isOK(\"s\"))"),
            (name: "testFailure_a", body: "XCTAssertFalse(isOK(\"u\"))"),
            (name: "testFailure_b", body: "XCTAssertFalse(isOK(\"v\"))"),
            (name: "testFailure_c", body: "XCTAssertFalse(isOK(\"w\"))"),
            (name: "testFailure_d", body: "XCTAssertFalse(isOK(\"t\"))")
        ])
        let candidates = EquivalenceClassMarkerExtractor.extract(
            methods: methods, slices: slices, markerTable: MarkerTable.curatedPairs
        )
        #expect(candidates.count == 1)
        let candidate = candidates[0]
        #expect(candidate.predicateName == "isOK")
        #expect(candidate.markerPair == MarkerPair(positive: "Success", negative: "Failure"))
        #expect(candidate.positiveSites.count == 4)
        #expect(candidate.negativeSites.count == 4)
    }

    @Test("Tie on site count — alphabetical tie-break by markerPair.positive picks the lexically smaller pair")
    func multiPairFireRankingTieBreakAlphabetical() {
        // Both Pass/Fail and Valid/Invalid hit isOK with 6 sites each.
        // Tie-break is alphabetical on .positive: "Pass" < "Valid" so
        // Pass/Fail wins.
        let (methods, slices) = Self.parsedCorpus([
            (name: "testValid_a", body: "XCTAssertTrue(isOK(\"a\"))"),
            (name: "testValid_b", body: "XCTAssertTrue(isOK(\"b\"))"),
            (name: "testValid_c", body: "XCTAssertTrue(isOK(\"c\"))"),
            (name: "testInvalid_a", body: "XCTAssertFalse(isOK(\"x\"))"),
            (name: "testInvalid_b", body: "XCTAssertFalse(isOK(\"y\"))"),
            (name: "testInvalid_c", body: "XCTAssertFalse(isOK(\"z\"))"),
            (name: "testPass_a", body: "XCTAssertTrue(isOK(\"p\"))"),
            (name: "testPass_b", body: "XCTAssertTrue(isOK(\"q\"))"),
            (name: "testPass_c", body: "XCTAssertTrue(isOK(\"r\"))"),
            (name: "testFail_a", body: "XCTAssertFalse(isOK(\"u\"))"),
            (name: "testFail_b", body: "XCTAssertFalse(isOK(\"v\"))"),
            (name: "testFail_c", body: "XCTAssertFalse(isOK(\"w\"))")
        ])
        let candidates = EquivalenceClassMarkerExtractor.extract(
            methods: methods, slices: slices, markerTable: MarkerTable.curatedPairs
        )
        #expect(candidates.count == 1)
        #expect(candidates[0].markerPair
            == MarkerPair(positive: "Pass", negative: "Fail"))
    }

    @Test("Different predicates with different pair winners are both retained")
    func multiPredicateMultiPairAllRetained() {
        let (methods, slices) = Self.parsedCorpus([
            // checkA wins under Valid/Invalid (6 sites) over Pass/Fail (3+0 → no second bucket so no candidate anyway)
            (name: "testValid_a1", body: "XCTAssertTrue(checkA(\"a\"))"),
            (name: "testValid_a2", body: "XCTAssertTrue(checkA(\"b\"))"),
            (name: "testValid_a3", body: "XCTAssertTrue(checkA(\"c\"))"),
            (name: "testInvalid_a1", body: "XCTAssertFalse(checkA(\"x\"))"),
            (name: "testInvalid_a2", body: "XCTAssertFalse(checkA(\"y\"))"),
            (name: "testInvalid_a3", body: "XCTAssertFalse(checkA(\"z\"))"),
            // checkB wins under Success/Failure (6 sites)
            (name: "testSuccess_b1", body: "XCTAssertTrue(checkB(\"a\"))"),
            (name: "testSuccess_b2", body: "XCTAssertTrue(checkB(\"b\"))"),
            (name: "testSuccess_b3", body: "XCTAssertTrue(checkB(\"c\"))"),
            (name: "testFailure_b1", body: "XCTAssertFalse(checkB(\"x\"))"),
            (name: "testFailure_b2", body: "XCTAssertFalse(checkB(\"y\"))"),
            (name: "testFailure_b3", body: "XCTAssertFalse(checkB(\"z\"))")
        ])
        let candidates = EquivalenceClassMarkerExtractor.extract(
            methods: methods, slices: slices, markerTable: MarkerTable.curatedPairs
        )
        #expect(candidates.count == 2)
        // Sorted by predicateName per finalize() contract
        #expect(candidates[0].predicateName == "checkA")
        #expect(candidates[0].markerPair == MarkerPair(positive: "Valid", negative: "Invalid"))
        #expect(candidates[1].predicateName == "checkB")
        #expect(candidates[1].markerPair == MarkerPair(positive: "Success", negative: "Failure"))
    }

    // MARK: - User-extensible vocabulary surface (forward-compat probe)

    @Test("User-supplied marker pair extends curated table — additional pair fires for its corpus")
    func userSuppliedPairExtendsCurated() {
        // Emulate the user-vocab-merge that lands at the discover-loop
        // call site (M13.1 keeps this concatenation at the caller; the
        // extractor is agnostic to where the table comes from).
        let userPairs = [MarkerPair(positive: "Open", negative: "Closed")]
        let table = MarkerTable.curatedPairs + userPairs
        let (methods, slices) = Self.parsedCorpus([
            (name: "testOpen_a", body: "XCTAssertTrue(isReady(\"a\"))"),
            (name: "testOpen_b", body: "XCTAssertTrue(isReady(\"b\"))"),
            (name: "testOpen_c", body: "XCTAssertTrue(isReady(\"c\"))"),
            (name: "testClosed_a", body: "XCTAssertFalse(isReady(\"x\"))"),
            (name: "testClosed_b", body: "XCTAssertFalse(isReady(\"y\"))"),
            (name: "testClosed_c", body: "XCTAssertFalse(isReady(\"z\"))")
        ])
        let candidates = EquivalenceClassMarkerExtractor.extract(
            methods: methods, slices: slices, markerTable: table
        )
        #expect(candidates.count == 1)
        #expect(candidates[0].predicateName == "isReady")
        #expect(candidates[0].markerPair == MarkerPair(positive: "Open", negative: "Closed"))
    }

    // MARK: - markerSet always nil at M13.1

    @Test("M13.1 extractor never populates markerSet — N-class lands in M13.2")
    func markerSetNilAtM13_1() {
        let (methods, slices) = Self.parsedCorpus([
            (name: "testValid_a", body: "XCTAssertTrue(isOK(\"a\"))"),
            (name: "testValid_b", body: "XCTAssertTrue(isOK(\"b\"))"),
            (name: "testValid_c", body: "XCTAssertTrue(isOK(\"c\"))"),
            (name: "testInvalid_a", body: "XCTAssertFalse(isOK(\"x\"))"),
            (name: "testInvalid_b", body: "XCTAssertFalse(isOK(\"y\"))"),
            (name: "testInvalid_c", body: "XCTAssertFalse(isOK(\"z\"))")
        ])
        let candidates = EquivalenceClassMarkerExtractor.extract(
            methods: methods, slices: slices, markerTable: MarkerTable.curatedPairs
        )
        #expect(candidates.allSatisfy { $0.markerSet == nil })
        #expect(candidates.allSatisfy { $0.markerPair != nil })
    }
}
