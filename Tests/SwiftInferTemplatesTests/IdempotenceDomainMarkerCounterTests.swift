import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

// V1.15.1 — domain-marker counter-signal on IdempotenceTemplate.
// Closes post-v1.14 priority #1: 7 OC HashTable idempotence Possible-
// tier survivors with first-parameter labels in
// DomainMarkerLabels.curated (forScale / forCapacity / forBucketContents).
//
// First cycle to ship a single mechanism applied to three templates
// simultaneously (cycles 7-9 deployed direction-label counter across
// three releases; v1.15 compresses the cadence into one).
//
// Score arithmetic for idempotence (baseline +30 typeSymmetry):
//   bare typeSymmetry            : +30  → Possible
//   bare + domain-marker counter : +30 - 15 = +15 → Suppressed
//   curated verb (+40)           : +40 + 30 = +70 → Likely
//   curated verb + counter       : +70 - 15 = +55 → Likely (preserved)

@Suite("IdempotenceTemplate — V1.15.1 domain-marker counter-signal")
struct IdempotenceDomainMarkerCounterTests {

    // MARK: - Suppression cases (the cycle-11 OC HashTable survivor pattern)

    @Test("V1.15.1 — `minimumCapacity(forScale:)` (Int) -> Int is suppressed")
    func minimumCapacityForScaleSuppressed() {
        // The textbook cycle-11 OC HashTable survivor case.
        // typeSymmetry +30, domain-marker -15 = +15 → Suppressed.
        let summary = makeIdempotenceSummary(
            name: "minimumCapacity",
            label: "forScale",
            paramType: "Int",
            returnType: "Int"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion == nil, "Domain-marker labeled (T) -> T should be suppressed")
    }

    @Test("V1.15.1 — `scale(forCapacity:)` (Int) -> Int is suppressed")
    func scaleForCapacitySuppressed() {
        let summary = makeIdempotenceSummary(
            name: "scale",
            label: "forCapacity",
            paramType: "Int",
            returnType: "Int"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion == nil)
    }

    @Test("V1.15.1 — all curated domain-marker labels suppress",
          arguments: ["forScale", "forCapacity", "forBucketContents"])
    func allCuratedDomainMarkerLabelsSuppress(label: String) {
        let summary = makeIdempotenceSummary(
            name: "convert",
            label: label,
            paramType: "Int",
            returnType: "Int"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion == nil, "Domain-marker label '\(label)' should suppress")
    }

    // MARK: - Non-suppression cases (preserve well-named idempotents)

    @Test("V1.15.1 — `normalize(forScale:)` (curated verb + domain marker) stays Likely")
    func curatedVerbWithDomainMarkerStillSurfaces() {
        // Curated verb +40 overrides the domain-marker counter via the
        // additive arithmetic: +30 + 40 - 15 = +55 → Likely.
        let summary = makeIdempotenceSummary(
            name: "normalize",
            label: "forScale",
            paramType: "Int",
            returnType: "Int"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 55)
        #expect(suggestion?.score.tier == .likely)
        #expect(suggestion?.score.signals.contains { $0.kind == .directionLabel } ?? false)
        #expect(suggestion?.score.signals.contains { $0.kind == .exactNameMatch } ?? false)
    }

    @Test("V1.15.1 — non-domain label `forX` (not in curated set) does NOT suppress")
    func nonCuratedForLabelDoesNotSuppress() {
        // `forSlot` / `forIndex` etc. are deliberately *not* in the
        // initial curated set per V1.15.0 plan open decision #3
        // (witnessed-only). Verifies the gate is tight.
        let summary = makeIdempotenceSummary(
            name: "process",
            label: "forSlot",
            paramType: "Int",
            returnType: "Int"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 30)
        #expect(suggestion?.score.tier == .possible)
    }

    @Test("V1.15.1 — `process(value:)` (non-domain label) still scores 30 (Possible)")
    func nonDomainLabelDoesNotSuppress() {
        let summary = makeIdempotenceSummary(
            name: "process",
            label: "value",
            paramType: "String",
            returnType: "String"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 30)
        #expect(suggestion?.score.tier == .possible)
    }

    @Test("V1.15.1 — `process(_:)` (nil label) still scores 30 (Possible)")
    func nilLabelDoesNotSuppress() {
        let summary = makeIdempotenceSummary(
            name: "process",
            label: nil,
            paramType: "String",
            returnType: "String"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 30)
        #expect(suggestion?.score.tier == .possible)
    }

    // MARK: - Boundary + design cases

    @Test("V1.15.1 — domain-marker label is case-sensitive (`ForScale` does not suppress)")
    func caseSensitive() {
        let summary = makeIdempotenceSummary(
            name: "process",
            label: "ForScale",
            paramType: "Int",
            returnType: "Int"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 30)
        #expect(suggestion?.score.tier == .possible)
    }

    @Test("V1.15.1 — counter weight is exactly -15")
    func counterWeightIsMinusFifteen() {
        let summary = makeIdempotenceSummary(
            name: "step",
            label: "forScale",
            paramType: "Int",
            returnType: "Int"
        )
        let signal = IdempotenceTemplate.domainMarkerCounterSignal(for: summary)
        #expect(signal?.weight == -15)
        #expect(signal?.kind == .directionLabel)
    }

    @Test("V1.15.1 — DomainMarkerLabels.curated lives in SwiftInferCore (canonical from cycle 1)")
    func domainMarkerLabelsLiveInCore() {
        // V1.15.1 lands the curated set directly at
        // SwiftInferCore.DomainMarkerLabels.curated without a per-
        // template intermediate, applying the v1.13 hoist lesson +
        // V1.14.1 SetAlgebraShape factoring posture preemptively.
        #expect(DomainMarkerLabels.curated.count == 3)
        let expected: Set<String> = ["forScale", "forCapacity", "forBucketContents"]
        #expect(DomainMarkerLabels.curated == expected)
    }

    @Test("V1.15.1 — direction-label and domain-marker are disjoint by intent")
    func directionLabelsAndDomainMarkersDisjoint() {
        // Distinct mechanism classes per the V1.15.0 plan: direction
        // labels are spatial-sequence iteration markers (after / before
        // / next / prev / ...); domain markers are named-domain
        // semantic-intent markers (forScale / forCapacity / ...).
        // The curated sets must remain textually disjoint.
        let intersection = DirectionLabels.curated.intersection(DomainMarkerLabels.curated)
        #expect(intersection.isEmpty, "Direction-label and domain-marker sets must not overlap")
    }

    // MARK: - Fixtures

    private func makeIdempotenceSummary(
        name: String,
        label: String?,
        paramType: String,
        returnType: String
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(
                    label: label,
                    internalName: "x",
                    typeText: paramType,
                    isInout: false
                )
            ],
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }
}

@Suite("IdempotenceTemplate — V1.15.1 end-to-end discover() integration")
struct IdempotenceDomainMarkerDiscoverTests {

    @Test("V1.15.1 — `minimumCapacity(forScale:)` no longer surfaces in discover()")
    func hashTableIdempotenceSuppressedEndToEnd() {
        let summary = makeSummary(name: "minimumCapacity", label: "forScale")
        let suggestions = TemplateRegistry.discover(in: [summary], typeDecls: [])
        let idempotenceCount = suggestions.filter { $0.templateName == "idempotence" }.count
        #expect(idempotenceCount == 0, "Domain-marker labeled idempotence should not surface")
    }

    @Test("V1.15.1 — non-domain idempotence still surfaces")
    func nonDomainIdempotenceStillSurfaces() {
        let summary = makeSummary(name: "process", label: "value")
        let suggestions = TemplateRegistry.discover(in: [summary], typeDecls: [])
        let idempotence = suggestions.first { $0.templateName == "idempotence" }
        #expect(idempotence != nil, "Non-domain-marker (T) -> T should still surface")
    }

    private func makeSummary(name: String, label: String?) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: label, internalName: "x", typeText: "Int", isInout: false)],
            returnTypeText: "Int",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }
}
