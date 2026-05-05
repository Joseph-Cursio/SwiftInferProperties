import Testing
import SwiftInferCore
@testable import SwiftInferTestLifter

@Suite("PredicateEquivalenceClassDetector — threshold + veto (M11.1)")
struct PredicateEquivalenceClassDetectorTests {

    // MARK: - Fixtures

    private static let validInvalidPair = MarkerPair(positive: "Valid", negative: "Invalid")

    /// Build a `FunctionSummary` that passes every veto check by default —
    /// single non-throwing, non-async parameter with `String` arg type.
    /// Tests override fields for the negative-path veto cases.
    private static func unaryPredicate(
        name: String = "isValid",
        argType: String = "String",
        isThrows: Bool = false,
        isAsync: Bool = false,
        parameterCount: Int = 1
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: (0..<parameterCount).map { idx in
                Parameter(label: nil, internalName: "p\(idx)", typeText: argType, isInout: false)
            },
            returnTypeText: "Bool",
            isThrows: isThrows,
            isAsync: isAsync,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Validator.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }

    private static func candidate(
        predicateName: String = "isValid",
        positiveCount: Int = 5,
        negativeCount: Int = 4,
        outlierCount: Int = 0
    ) -> PartitionCandidate {
        PartitionCandidate(
            predicateName: predicateName,
            markerPair: Self.validInvalidPair,
            positiveSites: (0..<positiveCount).map { PartitionSite(methodName: "testValid_\($0)") },
            negativeSites: (0..<negativeCount).map { PartitionSite(methodName: "testInvalid_\($0)") },
            outlierSiteCount: outlierCount
        )
    }

    // MARK: - Acceptance: emit path

    @Test("Homogeneous candidate (5+4 sites, generatable arg, non-throwing) emits hint with no veto")
    func homogeneousEmitsHint() {
        let hint = PredicateEquivalenceClassDetector.detect(
            candidate: Self.candidate(),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true
        )
        #expect(hint != nil)
        #expect(hint?.predicateName == "isValid")
        #expect(hint?.argTypeName == "String")
        #expect(hint?.positiveSiteCount == 5)
        #expect(hint?.negativeSiteCount == 4)
        #expect(hint?.predicateVeto == nil)
        #expect(hint?.suggestedPositiveGenerator == "Gen<String>.gen().filter(isValid)")
        #expect(hint?.suggestedNegativeGenerator == "Gen<String>.gen().filter { !isValid($0) }")
    }

    @Test("Both buckets at threshold (3+3 sites) emits hint")
    func atThresholdEmitsHint() {
        let hint = PredicateEquivalenceClassDetector.detect(
            candidate: Self.candidate(positiveCount: 3, negativeCount: 3),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true
        )
        #expect(hint != nil)
        #expect(hint?.positiveSiteCount == 3)
        #expect(hint?.negativeSiteCount == 3)
    }

    // MARK: - Threshold

    @Test("Below positive-bucket threshold (2+5) → no hint")
    func belowPositiveThresholdNoHint() {
        let hint = PredicateEquivalenceClassDetector.detect(
            candidate: Self.candidate(positiveCount: 2, negativeCount: 5),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true
        )
        #expect(hint == nil)
    }

    @Test("Below negative-bucket threshold (5+2) → no hint")
    func belowNegativeThresholdNoHint() {
        let hint = PredicateEquivalenceClassDetector.detect(
            candidate: Self.candidate(positiveCount: 5, negativeCount: 2),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true
        )
        #expect(hint == nil)
    }

    @Test("Both buckets below threshold (2+2) → no hint")
    func bothBucketsBelowThresholdNoHint() {
        let hint = PredicateEquivalenceClassDetector.detect(
            candidate: Self.candidate(positiveCount: 2, negativeCount: 2),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true
        )
        #expect(hint == nil)
    }

    // MARK: - Conservative bias: outlier kills

    @Test("Any outlier in candidate kills the hint (PRD §3.5)")
    func singleOutlierKills() {
        let hint = PredicateEquivalenceClassDetector.detect(
            candidate: Self.candidate(outlierCount: 1),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true
        )
        #expect(hint == nil)
    }

    // MARK: - Predicate-shape veto (mirrors M10.2 producer-veto rules)

    @Test("Throwing predicate emits hint with .predicateThrows veto")
    func throwingPredicateVetoes() {
        let hint = PredicateEquivalenceClassDetector.detect(
            candidate: Self.candidate(),
            predicateSummary: Self.unaryPredicate(isThrows: true),
            predicateArgGeneratable: true
        )
        #expect(hint != nil)
        #expect(hint?.predicateVeto == .predicateThrows)
    }

    @Test("Async predicate emits hint with .predicateAsync veto")
    func asyncPredicateVetoes() {
        let hint = PredicateEquivalenceClassDetector.detect(
            candidate: Self.candidate(),
            predicateSummary: Self.unaryPredicate(isAsync: true),
            predicateArgGeneratable: true
        )
        #expect(hint != nil)
        #expect(hint?.predicateVeto == .predicateAsync)
    }

    @Test("Multi-arg predicate emits hint with .predicateMultiArg veto")
    func multiArgPredicateVetoes() {
        let hint = PredicateEquivalenceClassDetector.detect(
            candidate: Self.candidate(),
            predicateSummary: Self.unaryPredicate(parameterCount: 2),
            predicateArgGeneratable: true
        )
        #expect(hint != nil)
        #expect(hint?.predicateVeto == .predicateMultiArg)
    }

    @Test("Non-generatable arg emits hint with .predicateArgNotGeneratable veto")
    func nonGeneratableArgVetoes() {
        let hint = PredicateEquivalenceClassDetector.detect(
            candidate: Self.candidate(),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: false
        )
        #expect(hint != nil)
        #expect(hint?.predicateVeto == .predicateArgNotGeneratable)
    }

    @Test("Veto priority: throws > async (both flags set surfaces .predicateThrows)")
    func vetoPriorityThrowsBeatsAsync() {
        let hint = PredicateEquivalenceClassDetector.detect(
            candidate: Self.candidate(),
            predicateSummary: Self.unaryPredicate(isThrows: true, isAsync: true),
            predicateArgGeneratable: true
        )
        #expect(hint?.predicateVeto == .predicateThrows)
    }

    // MARK: - Missing predicate summary

    @Test("Missing predicate summary emits hint with .predicateArgNotGeneratable veto + fallback typeName")
    func missingSummaryEmitsAdvisoryWithFallbackType() {
        let hint = PredicateEquivalenceClassDetector.detect(
            candidate: Self.candidate(),
            predicateSummary: nil,
            predicateArgGeneratable: false
        )
        #expect(hint != nil)
        #expect(hint?.predicateVeto == .predicateArgNotGeneratable)
        // The detector falls back to "T" when no signature is available.
        #expect(hint?.argTypeName == "T")
    }

    @Test("Generator expressions reflect the predicate's actual argType when summary present")
    func generatorExpressionsUseActualArgType() {
        let hint = PredicateEquivalenceClassDetector.detect(
            candidate: Self.candidate(predicateName: "isPositive"),
            predicateSummary: Self.unaryPredicate(name: "isPositive", argType: "Int"),
            predicateArgGeneratable: true
        )
        #expect(hint?.suggestedPositiveGenerator == "Gen<Int>.gen().filter(isPositive)")
        #expect(hint?.suggestedNegativeGenerator == "Gen<Int>.gen().filter { !isPositive($0) }")
    }
}
