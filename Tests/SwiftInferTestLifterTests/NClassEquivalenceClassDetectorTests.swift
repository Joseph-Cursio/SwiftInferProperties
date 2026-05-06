import Testing
import SwiftInferCore
@testable import SwiftInferTestLifter

@Suite("NClassEquivalenceClassDetector — N-class threshold + veto (M13.2)")
struct NClassEquivalenceClassDetectorTests {

    // MARK: - Fixtures

    private static let sizesMarkerSet = MarkerSet(
        name: "Sizes",
        markers: ["Small", "Medium", "Large"]
    )

    private static func unaryPredicate(
        name: String = "size",
        argType: String = "Box",
        returnType: String? = "Size",
        isThrows: Bool = false,
        isAsync: Bool = false,
        parameterCount: Int = 1
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: (0..<parameterCount).map { idx in
                Parameter(label: nil, internalName: "p\(idx)", typeText: argType, isInout: false)
            },
            returnTypeText: returnType,
            isThrows: isThrows,
            isAsync: isAsync,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Sizer.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }

    private static func candidate(
        predicateName: String = "size",
        bucketsByMarker: [String: Int] = ["Small": 3, "Medium": 3, "Large": 3],
        outlierCount: Int = 0,
        markerSet: MarkerSet? = nil
    ) -> PartitionCandidate {
        let resolvedSet = markerSet ?? Self.sizesMarkerSet
        let buckets = bucketsByMarker.mapValues { count in
            (0..<count).map { PartitionSite(methodName: "test_site_\($0)") }
        }
        return PartitionCandidate(
            predicateName: predicateName,
            markerPair: nil,
            markerSet: resolvedSet,
            positiveSites: [],
            negativeSites: [],
            nClassBucketsByMarker: buckets,
            outlierSiteCount: outlierCount
        )
    }

    // MARK: - Acceptance: emit path

    @Test("Three-bucket Small/Medium/Large with 3+ sites each emits hint with no veto")
    func threeClassEmitsHint() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.candidate(),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true
        )
        #expect(hint != nil)
        #expect(hint?.predicateName == "size")
        #expect(hint?.argTypeName == "Box")
        #expect(hint?.returnTypeName == "Size")
        #expect(hint?.markerSetName == "Sizes")
        #expect(hint?.markers == ["Small", "Medium", "Large"])
        #expect(hint?.predicateVeto == nil)
        #expect(hint?.siteCountsByMarker["Small"] == 3)
        #expect(hint?.siteCountsByMarker["Medium"] == 3)
        #expect(hint?.siteCountsByMarker["Large"] == 3)
    }

    @Test("Suggested generators use lowercase-first case literal convention")
    func generatorsUseLowercaseFirst() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.candidate(),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true
        )
        #expect(hint?.suggestedGeneratorsByMarker["Small"]
            == "Gen<Box>.gen().filter { size($0) == .small }")
        #expect(hint?.suggestedGeneratorsByMarker["Medium"]
            == "Gen<Box>.gen().filter { size($0) == .medium }")
        #expect(hint?.suggestedGeneratorsByMarker["Large"]
            == "Gen<Box>.gen().filter { size($0) == .large }")
    }

    @Test("Markers preserve marker-set declaration order in the hint")
    func markersPreserveOrder() {
        // The marker set declares ["Small", "Medium", "Large"]; even
        // if the dictionary iteration order is unstable, the hint's
        // `markers` array reflects the marker-set order.
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.candidate(),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true
        )
        #expect(hint?.markers == ["Small", "Medium", "Large"])
    }

    // MARK: - Threshold

    @Test("Bucket below threshold (Medium=2) drops out — only 2 active < 3 → no hint")
    func belowBucketThresholdDrops() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.candidate(bucketsByMarker: ["Small": 3, "Medium": 2, "Large": 3]),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true
        )
        // Two active buckets remain (Small + Large); minActiveBuckets = 3 → no hint.
        #expect(hint == nil)
    }

    @Test("Four-bucket marker set with one bucket below threshold still emits if 3 remain active")
    func fourBucketWithOneDroppedStillEmits() {
        let foursome = MarkerSet(
            name: "Sizes",
            markers: ["Small", "Medium", "Large", "ExtraLarge"]
        )
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.candidate(
                bucketsByMarker: ["Small": 3, "Medium": 3, "Large": 3, "ExtraLarge": 1],
                markerSet: foursome
            ),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true
        )
        #expect(hint != nil)
        // ExtraLarge dropped (only 1 site < 3); markers preserves order
        // for the remaining three.
        #expect(hint?.markers == ["Small", "Medium", "Large"])
        #expect(hint?.siteCountsByMarker["ExtraLarge"] == nil)
    }

    @Test("Below-minActiveBuckets emits no hint")
    func belowMinActiveBucketsNoHint() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.candidate(bucketsByMarker: ["Small": 3, "Medium": 3, "Large": 1]),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true
        )
        #expect(hint == nil)
    }

    // MARK: - Conservative bias: outlier kills

    @Test("Any outlier in candidate kills the hint (PRD §3.5)")
    func outlierKillsHint() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.candidate(outlierCount: 1),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true
        )
        #expect(hint == nil)
    }

    // MARK: - Carrier-shape guard

    @Test("Two-class candidate (markerSet == nil) is rejected — flow goes through M11.1 detector")
    func twoClassCandidateRejected() {
        let twoClassCandidate = PartitionCandidate(
            predicateName: "isOK",
            markerPair: MarkerPair(positive: "Valid", negative: "Invalid"),
            markerSet: nil,
            positiveSites: (0..<3).map { PartitionSite(methodName: "testValid_\($0)") },
            negativeSites: (0..<3).map { PartitionSite(methodName: "testInvalid_\($0)") },
            outlierSiteCount: 0
        )
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: twoClassCandidate,
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true
        )
        #expect(hint == nil)
    }

    @Test("N-class candidate without nClassBucketsByMarker is rejected")
    func nClassWithoutBucketsRejected() {
        let degenerate = PartitionCandidate(
            predicateName: "size",
            markerPair: nil,
            markerSet: Self.sizesMarkerSet,
            positiveSites: [],
            negativeSites: [],
            nClassBucketsByMarker: nil,
            outlierSiteCount: 0
        )
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: degenerate,
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true
        )
        #expect(hint == nil)
    }

    // Predicate-shape veto cases live in
    // `NClassEquivalenceClassDetectorVetoTests` (split out at M13.2 to
    // keep this file under SwiftLint's `type_body_length` cap).
}
