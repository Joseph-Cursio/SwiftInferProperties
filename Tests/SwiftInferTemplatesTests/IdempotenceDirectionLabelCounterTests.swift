import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// V1.10.1 — direction-label counter-signal on IdempotenceTemplate.
// Closes cycle-7 priority #1 from
// docs/calibration-cycle-6-findings.md (idempotence 0/10 acceptance
// rate; counter-signal targets the dominant 5-of-10 direction-labeled
// rejection sub-pattern). Split from IdempotenceTemplateTests.swift
// per the V1.7.1/V1.8.1 split precedent.

@Suite("IdempotenceTemplate — V1.10.1 direction-label counter-signal")
struct IdempotenceDirectionLabelCounterTests {

    // MARK: - Suppression cases (the cycle-6 rejection pattern)

    @Test("V1.10.1 — `index(after:)` (T) -> T is suppressed (Score 30 - 15 = 15)")
    func indexAfterSuppressed() {
        // Collection-protocol increment — the textbook cycle-6 reject case.
        // Score arithmetic: typeSymmetry +30, direction counter -15 = 15
        // → Suppressed tier (< 20).
        let summary = makeIdempotenceSummary(
            name: "index",
            parameters: [Parameter(label: "after", internalName: "i", typeText: "Index", isInout: false)],
            returnType: "Index"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion == nil, "Direction-labeled (T) -> T should be suppressed")
    }

    @Test("V1.10.1 — `index(before:)` (T) -> T is suppressed")
    func indexBeforeSuppressed() {
        let summary = makeIdempotenceSummary(
            name: "index",
            parameters: [Parameter(label: "before", internalName: "i", typeText: "Index", isInout: false)],
            returnType: "Index"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion == nil)
    }

    @Test("V1.10.1 — all curated direction labels suppress",
          arguments: [
              "after", "before", "next", "prev", "previous",
              "advance", "succ", "pred", "successor", "predecessor"
          ])
    func allCuratedDirectionLabelsSuppress(label: String) {
        let summary = makeIdempotenceSummary(
            name: "step",
            parameters: [Parameter(label: label, internalName: "v", typeText: "Int", isInout: false)],
            returnType: "Int"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion == nil, "Direction label '\(label)' should suppress idempotence")
    }

    // MARK: - Non-suppression cases (preserve well-named idempotents)

    @Test("V1.10.1 — `normalize(_:)` (no label) still scores 70 (Likely)")
    func curatedVerbNoLabelStillEmits() {
        // Existing V1.5.1 behavior preserved: no first-param label means
        // no direction counter; curated verb +40 fires; net +70 → Likely.
        let summary = makeIdempotenceSummary(
            name: "normalize",
            paramType: "String",
            returnType: "String"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
        #expect(!(suggestion?.score.signals.contains { $0.kind == .directionLabel } ?? false))
    }

    @Test("V1.10.1 — curated verb + direction label survives (curated wins)")
    func curatedVerbWithDirectionLabelStillSurfaces() {
        // Hypothetical: a function named `normalize(after:)` — curated
        // verb +40, type symmetry +30, direction counter -15 = +55
        // → Likely tier. The user's explicit `normalize` naming is a
        // strong positive signal that overrides the structural penalty.
        let summary = makeIdempotenceSummary(
            name: "normalize",
            parameters: [Parameter(label: "after", internalName: "v", typeText: "Int", isInout: false)],
            returnType: "Int"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 55)
        #expect(suggestion?.score.tier == .likely)
        #expect(suggestion?.score.signals.contains { $0.kind == .directionLabel } ?? false)
        #expect(suggestion?.score.signals.contains { $0.kind == .exactNameMatch } ?? false)
    }

    @Test("V1.10.1 — `process(value:)` (non-direction label) still scores 30 (Possible)")
    func nonDirectionLabelDoesNotSuppress() {
        // Existing behavior preserved for non-direction labels.
        let summary = makeIdempotenceSummary(
            name: "process",
            parameters: [Parameter(label: "value", internalName: "v", typeText: "String", isInout: false)],
            returnType: "String"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 30)
        #expect(suggestion?.score.tier == .possible)
    }

    @Test("V1.10.1 — `process(_:)` (nil label) still scores 30 (Possible)")
    func nilLabelDoesNotSuppress() {
        let summary = makeIdempotenceSummary(
            name: "process",
            paramType: "String",
            returnType: "String"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 30)
        #expect(suggestion?.score.tier == .possible)
        #expect(!(suggestion?.score.signals.contains { $0.kind == .directionLabel } ?? false))
    }

    // MARK: - Boundary cases

    @Test("V1.10.1 — direction label is case-sensitive (`After` does not suppress)")
    func caseSensitive() {
        // The curated set has lowercased entries. Swift convention is
        // lowerCamelCase for arg labels, so `After` is non-conventional;
        // we don't try to match it.
        let summary = makeIdempotenceSummary(
            name: "step",
            parameters: [Parameter(label: "After", internalName: "v", typeText: "Int", isInout: false)],
            returnType: "Int"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 30, "Mismatched case shouldn't trigger the counter")
    }

    @Test("V1.10.1 — counter only checks first-param label (multi-param shape doesn't apply)")
    func onlyFirstParamConsidered() {
        // Idempotence type pattern requires single-param (T) -> T anyway;
        // this is a defensive test that the helper reads
        // parameters.first?.label, not parameters.last or any.
        // Idempotence rejects the multi-param shape upstream; just confirm
        // the helper signature respects single-param expectation.
        let summary = makeIdempotenceSummary(
            name: "idx",
            parameters: [Parameter(label: "after", internalName: "i", typeText: "Int", isInout: false)],
            returnType: "Int"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion == nil)
    }

    @Test("V1.10.1 — Signal.Kind.directionLabel is in CaseIterable")
    func signalKindAddedToCaseIterable() {
        // Defensive — guards against future enum-case removal breaking
        // calibration trajectory.
        #expect(Signal.Kind.allCases.contains(.directionLabel))
    }

    @Test("V1.13.1 — DirectionLabels.curated set has 10 entries (hoisted from IdempotenceTemplate)")
    func curatedSetSize() {
        // Pinning the count guards against silent set drift; future
        // additions should update this assertion + the rubric.
        // V1.13.1 hoisted from `IdempotenceTemplate.directionLabels`
        // to `SwiftInferCore.DirectionLabels.curated` once round-trip
        // became the third consumer in cycle 9.
        #expect(DirectionLabels.curated.count == 10)
        let expected: Set<String> = [
            "after", "before",
            "next", "prev", "previous",
            "advance", "succ", "pred", "successor", "predecessor"
        ]
        #expect(DirectionLabels.curated == expected)
    }
}

@Suite("IdempotenceTemplate — V1.10.1 end-to-end discover() integration")
struct IdempotenceDirectionLabelDiscoverTests {

    @Test("V1.10.1 — `index(after:)` no longer surfaces in discover() output")
    func indexAfterSuppressedEndToEnd() {
        let indexAfter = makeIdempotenceSummary(
            name: "index",
            parameters: [Parameter(label: "after", internalName: "i", typeText: "Int", isInout: false)],
            returnType: "Int"
        )
        let suggestions = TemplateRegistry.discover(in: [indexAfter], typeDecls: [])
        let idempotenceCount = suggestions.filter { $0.templateName == "idempotence" }.count
        #expect(idempotenceCount == 0)
    }

    @Test("V1.10.1 — `normalize(_:)` still surfaces at Likely tier")
    func normalizeStillSurfaces() {
        let normalize = makeIdempotenceSummary(
            name: "normalize",
            paramType: "String",
            returnType: "String"
        )
        let suggestions = TemplateRegistry.discover(in: [normalize], typeDecls: [])
        let idempotence = suggestions.first { $0.templateName == "idempotence" }
        #expect(idempotence != nil)
        #expect(idempotence?.score.tier == .likely)
    }
}
