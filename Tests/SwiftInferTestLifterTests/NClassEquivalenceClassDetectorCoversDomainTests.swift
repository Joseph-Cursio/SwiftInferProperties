import SwiftInferCore
@testable import SwiftInferTestLifter
import Testing

@Suite("NClassEquivalenceClassDetector — coversDomain via same-target enum (M14.1)")
struct NClassDetectorCoversDomainTests {

    // MARK: - Fixtures

    private static let sizesMarkerSet = MarkerSet(
        name: "Sizes",
        markers: ["Small", "Medium", "Large"]
    )

    private static func unaryPredicate(
        returnType: String? = "Size"
    ) -> FunctionSummary {
        FunctionSummary(
            name: "size",
            parameters: [Parameter(label: nil, internalName: "p0", typeText: "Box", isInout: false)],
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Sizer.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }

    private static func threshholdCandidate(
        markerSet: MarkerSet? = nil
    ) -> PartitionCandidate {
        let resolvedSet = markerSet ?? Self.sizesMarkerSet
        let buckets = ["Small": 3, "Medium": 3, "Large": 3].mapValues { count in
            (0..<count).map { PartitionSite(methodName: "test_site_\($0)") }
        }
        return PartitionCandidate(
            predicateName: "size",
            markerPair: nil,
            markerSet: resolvedSet,
            positiveSites: [],
            negativeSites: [],
            nClassBucketsByMarker: buckets,
            outlierSiteCount: 0
        )
    }

    private static func sizeEnumDecl(cases: [String]) -> TypeDecl {
        TypeDecl(
            name: "Size",
            kind: .enum,
            inheritedTypes: ["Equatable"],
            location: SourceLocation(file: "Sizer.swift", line: 1, column: 1),
            enumCaseNames: cases
        )
    }

    // MARK: - Full coverage → coversDomain = true

    @Test("Marker set covers every enum case → coversDomain == true")
    func fullCoverageEmitsCoversDomainTrue() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true,
            typeDecls: [Self.sizeEnumDecl(cases: ["small", "medium", "large"])]
        )
        #expect(hint?.coversDomain == true)
    }

    @Test("Case-insensitive marker match — Title-case markers vs lowercase enum cases")
    func caseInsensitiveMarkerMatch() {
        // Markers are "Small"/"Medium"/"Large" (Title-case);
        // enum cases are "small"/"medium"/"large" (Swift convention).
        // Coverage must match case-insensitively.
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true,
            typeDecls: [Self.sizeEnumDecl(cases: ["small", "medium", "large"])]
        )
        #expect(hint?.coversDomain == true)
    }

    // MARK: - Partial coverage → coversDomain = false

    @Test("Marker set missing one enum case → coversDomain == false")
    func partialCoverageDropsCoversDomain() {
        // Enum has four cases, marker set covers only three.
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true,
            typeDecls: [Self.sizeEnumDecl(cases: ["small", "medium", "large", "extraLarge"])]
        )
        #expect(hint?.coversDomain == false)
    }

    @Test("Marker set has extra markers not in enum → coversDomain == true (over-coverage is fine)")
    func overCoverageStillCoversDomain() {
        // Enum has three cases, marker set covers them plus one extra.
        // The extra marker doesn't break coverage; every enum case is
        // still covered.
        let extraMarkerSet = MarkerSet(
            name: "Sizes",
            markers: ["Small", "Medium", "Large", "Extra"]
        )
        // Need ≥ 3 active buckets (each ≥ 3 sites). The "Extra" bucket
        // has zero sites so it drops out of activeMarkers; the
        // remaining three reach threshold.
        let buckets: [String: Int] = ["Small": 3, "Medium": 3, "Large": 3]
        let candidate = PartitionCandidate(
            predicateName: "size",
            markerPair: nil,
            markerSet: extraMarkerSet,
            positiveSites: [], negativeSites: [],
            nClassBucketsByMarker: buckets.mapValues { count in
                (0..<count).map { PartitionSite(methodName: "test_\($0)") }
            },
            outlierSiteCount: 0
        )
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: candidate,
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true,
            typeDecls: [Self.sizeEnumDecl(cases: ["small", "medium", "large"])]
        )
        #expect(hint?.coversDomain == true)
    }

    // MARK: - Cross-target / unresolved → coversDomain = false

    @Test("No same-target TypeDecl for the return type → coversDomain == false (cross-target conservative)")
    func crossTargetReturnTypeDropsCoversDomain() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true,
            typeDecls: []
        )
        #expect(hint?.coversDomain == false)
    }

    @Test("typeDecls includes other types but not the return type → coversDomain == false")
    func unrelatedTypeDeclsDropsCoversDomain() {
        let other = TypeDecl(
            name: "Color",
            kind: .enum,
            inheritedTypes: [],
            location: SourceLocation(file: "T.swift", line: 1, column: 1),
            enumCaseNames: ["red", "green", "blue"]
        )
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true,
            typeDecls: [other]
        )
        #expect(hint?.coversDomain == false)
    }

    // MARK: - Empty enum

    @Test("Empty enum (no cases) → coversDomain == false (degenerate, no claim)")
    func emptyEnumNoCoverage() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true,
            typeDecls: [Self.sizeEnumDecl(cases: [])]
        )
        #expect(hint?.coversDomain == false)
    }

    // MARK: - Extension union (M14 plan OD #1)

    @Test("Extension adds a case → primary + extension union covered → coversDomain == true")
    func extensionCaseUnionCovered() {
        let primary = TypeDecl(
            name: "Size",
            kind: .enum,
            inheritedTypes: [],
            location: SourceLocation(file: "Size.swift", line: 1, column: 1),
            enumCaseNames: ["small", "medium"]
        )
        let extensionDecl = TypeDecl(
            name: "Size",
            kind: .extension,
            inheritedTypes: [],
            location: SourceLocation(file: "Size+Extra.swift", line: 1, column: 1),
            enumCaseNames: ["large"]
        )
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true,
            typeDecls: [primary, extensionDecl]
        )
        #expect(hint?.coversDomain == true)
    }

    @Test("Extension adds a case the marker set doesn't cover → coversDomain == false")
    func extensionCaseUnionPartialCoverage() {
        let primary = TypeDecl(
            name: "Size",
            kind: .enum,
            inheritedTypes: [],
            location: SourceLocation(file: "Size.swift", line: 1, column: 1),
            enumCaseNames: ["small", "medium", "large"]
        )
        let extensionDecl = TypeDecl(
            name: "Size",
            kind: .extension,
            inheritedTypes: [],
            location: SourceLocation(file: "Size+Extra.swift", line: 1, column: 1),
            enumCaseNames: ["extraLarge"]
        )
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true,
            typeDecls: [primary, extensionDecl]
        )
        #expect(hint?.coversDomain == false)
    }

    // MARK: - Optional return type (M14 plan OD #6)

    @Test("Optional enum return type → coversDomain == false (nil is in the value space)")
    func optionalReturnTypeDropsCoversDomain() {
        // Predicate returns `Size?`; even if every Size case is in the
        // marker set, the `nil` value isn't covered, so the partition
        // doesn't actually cover the domain.
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(returnType: "Size?"),
            predicateArgGeneratable: true,
            typeDecls: [Self.sizeEnumDecl(cases: ["small", "medium", "large"])]
        )
        #expect(hint?.coversDomain == false)
    }

    // MARK: - Non-identifier return types

    @Test("Function-typed return → coversDomain == false (rejected by veto + by name lookup)")
    func functionTypedReturnDropsCoversDomain() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(returnType: "(Int) -> Bool"),
            predicateArgGeneratable: true,
            typeDecls: [Self.sizeEnumDecl(cases: ["small", "medium", "large"])]
        )
        // Outer veto fires first (.predicateReturnNotEquatable), but
        // even if it didn't, coversDomain would be false.
        #expect(hint?.coversDomain == false)
    }

    @Test("Tuple return → coversDomain == false")
    func tupleReturnDropsCoversDomain() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(returnType: "(Int, Int)"),
            predicateArgGeneratable: true,
            typeDecls: [Self.sizeEnumDecl(cases: ["small", "medium", "large"])]
        )
        #expect(hint?.coversDomain == false)
    }

    // MARK: - Default param back-compat

    @Test("typeDecls defaults to [] — M13.2 callers continue to compile and produce coversDomain == false")
    func defaultParamBackCompat() {
        let hint = NClassEquivalenceClassDetector.detect(
            candidate: Self.threshholdCandidate(),
            predicateSummary: Self.unaryPredicate(),
            predicateArgGeneratable: true
        )
        #expect(hint?.coversDomain == false)
    }
}
