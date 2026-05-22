import SwiftInferCore
@testable import SwiftInferTestLifter
import Testing

@Suite("NClassEquivalenceClassDetector — predicate-shape veto (M13.2)")
struct NClassEquivalenceClassDetectorVetoTests {

    // MARK: - Fixtures (mirrored from NClassEquivalenceClassDetectorTests)

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

    private static func threshholdCandidate() -> PartitionCandidate {
        let buckets = ["Small": 3, "Medium": 3, "Large": 3].mapValues { count in
            (0..<count).map { PartitionSite(methodName: "test_site_\($0)") }
        }
        return PartitionCandidate(
            predicateName: "size",
            markerPair: nil,
            markerSet: Self.sizesMarkerSet,
            positiveSites: [],
            negativeSites: [],
            nClassBucketsByMarker: buckets,
            outlierSiteCount: 0
        )
    }

    // MARK: - M11 vetoes verbatim

    @Test("Throwing predicate emits hint with .predicateThrows veto")
    func throwingPredicateVetoes() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(isThrows: true),
            predicateArgGeneratable: true
        )
        #expect(hint != nil)
        #expect(hint?.predicateVeto == .predicateThrows)
    }

    @Test("Async predicate emits hint with .predicateAsync veto")
    func asyncPredicateVetoes() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(isAsync: true),
            predicateArgGeneratable: true
        )
        #expect(hint?.predicateVeto == .predicateAsync)
    }

    @Test("Multi-arg predicate emits hint with .predicateMultiArg veto")
    func multiArgPredicateVetoes() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(parameterCount: 2),
            predicateArgGeneratable: true
        )
        #expect(hint?.predicateVeto == .predicateMultiArg)
    }

    @Test("Non-generatable arg emits hint with .predicateArgNotGeneratable veto")
    func nonGeneratableArgVetoes() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: false
        )
        #expect(hint?.predicateVeto == .predicateArgNotGeneratable)
    }

    // MARK: - New M13.2 veto: predicateReturnNotEquatable

    @Test("Function-typed return emits hint with .predicateReturnNotEquatable veto")
    func functionReturnTypeVetoes() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(returnType: "(Int) -> Bool"),
            predicateArgGeneratable: true
        )
        #expect(hint?.predicateVeto == .predicateReturnNotEquatable)
    }

    @Test("Generic-placeholder return type emits hint with .predicateReturnNotEquatable veto")
    func genericPlaceholderReturnTypeVetoes() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(returnType: "T"),
            predicateArgGeneratable: true
        )
        #expect(hint?.predicateVeto == .predicateReturnNotEquatable)
    }

    @Test("Tuple return type emits hint with .predicateReturnNotEquatable veto")
    func tupleReturnTypeVetoes() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(returnType: "(Int, Int)"),
            predicateArgGeneratable: true
        )
        #expect(hint?.predicateVeto == .predicateReturnNotEquatable)
    }

    @Test("Nil return type emits hint with .predicateReturnNotEquatable veto")
    func nilReturnTypeVetoes() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(returnType: nil),
            predicateArgGeneratable: true
        )
        #expect(hint?.predicateVeto == .predicateReturnNotEquatable)
    }

    @Test("Optional enum return type accepted (Equatable assumed)")
    func optionalEnumReturnTypeAccepted() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(returnType: "Size?"),
            predicateArgGeneratable: true
        )
        #expect(hint?.predicateVeto == nil)
    }

    // MARK: - Veto priority + missing summary

    @Test("Veto priority: throws > async (both flags set surfaces .predicateThrows)")
    func vetoPriorityThrowsBeatsAsync() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(isThrows: true, isAsync: true),
            predicateArgGeneratable: true
        )
        #expect(hint?.predicateVeto == .predicateThrows)
    }

    @Test("Missing predicate summary emits hint with .predicateArgNotGeneratable veto + fallback typeName")
    func missingSummaryEmitsAdvisory() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: nil,
            predicateArgGeneratable: false
        )
        #expect(hint != nil)
        #expect(hint?.predicateVeto == .predicateArgNotGeneratable)
        #expect(hint?.argTypeName == "T")
        #expect(hint?.returnTypeName == "<unknown>")
    }
}
