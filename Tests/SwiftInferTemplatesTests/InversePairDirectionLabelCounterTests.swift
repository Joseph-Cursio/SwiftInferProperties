import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

// V1.11.1 — direction-label counter-signal on InversePairTemplate.
// Closes cycle-8 priority #1 from
// docs/calibration-cycle-7-findings.md (inverse-pair 0/5 acceptance
// rate per cycle-6's measurement; counter-signal targets the dominant
// 2-of-5 direction-labeled rejection sub-pattern). Mirrors v1.10's
// IdempotenceDirectionLabelCounterTests shape; reuses
// IdempotenceTemplate.directionLabels via cross-template static access
// (open decision #2 in v1.11 plan).

@Suite("InversePairTemplate — V1.11.1 direction-label counter-signal")
struct InversePairDirectionLabelCounterTests {

    // MARK: - Suppression cases (the cycle-6 inverse-pair rejection pattern)

    @Test("V1.11.1 — `index(after:) ↔ index(before:)` is suppressed (Score 25 - 10 = 15)")
    func indexAfterIndexBeforeSuppressed() {
        // Collection-protocol pair — the textbook cycle-6 reject case
        // (picks #48-#49, Algorithms `(Index) -> Index` ops). Score
        // arithmetic: typeSymmetry +25, direction counter -10 = 15
        // → Suppressed tier (< 20).
        let pair = makePair(
            forwardName: "index",
            forwardLabel: "after",
            reverseName: "index",
            reverseLabel: "before",
            forwardParam: "Index",
            forwardReturn: "Index"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion == nil, "Direction-labeled inverse pair should be suppressed")
    }

    @Test("V1.11.1 — `bucket(after:) ↔ bucket(before:)` is suppressed")
    func bucketAfterBucketBeforeSuppressed() {
        let pair = makePair(
            forwardName: "bucket",
            forwardLabel: "after",
            reverseName: "bucket",
            reverseLabel: "before",
            forwardParam: "Bucket",
            forwardReturn: "Bucket"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion == nil)
    }

    @Test(
        "V1.11.1 — all curated direction labels suppress (forward-side)",
        arguments: ["after", "before", "next", "prev", "previous",
                    "advance", "succ", "pred", "successor", "predecessor"]
    )
    func allCuratedDirectionLabelsSuppressForwardSide(label: String) {
        let pair = makePair(
            forwardName: "step",
            forwardLabel: label,
            reverseName: "unstep",
            reverseLabel: nil,
            forwardParam: "Token",
            forwardReturn: "Token"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion == nil, "Forward direction label '\(label)' should suppress")
    }

    @Test(
        "V1.11.1 — direction label on reverse side alone also suppresses",
        arguments: ["after", "before", "next", "prev", "previous",
                    "advance", "succ", "pred", "successor", "predecessor"]
    )
    func directionLabelOnReverseSuppresses(label: String) {
        // Either-side detection: open decision #3. Asymmetric labeling
        // (forward unlabeled, reverse direction-labeled) should still
        // suppress. Non-curated names (`transform`/`untransform` are
        // not in `RoundTripTemplate.curatedInversePairs`) so the
        // baseline is bare typeSymmetry +25; reverse-side direction
        // label -10 = 15 → Suppressed.
        let pair = makePair(
            forwardName: "transform",
            forwardLabel: nil,
            reverseName: "untransform",
            reverseLabel: label,
            forwardParam: "Token",
            forwardReturn: "Token"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion == nil, "Reverse direction label '\(label)' should suppress")
    }

    // MARK: - Non-suppression cases (preserve well-named inverse pairs)

    @Test("V1.11.1 — `parse(_:) ↔ format(_:)` (no direction labels) still scores 25 (Possible)")
    func curatedNamePairNoDirectionStillEmits() {
        // Existing V1.4.3 / V1.5.2 behavior preserved: no direction labels
        // means no counter-signal; type symmetry +25 alone → Possible.
        // (`parse`/`format` is in `RoundTripTemplate.curatedInversePairs`
        // — but the curated-name match needs the curated tuple, which
        // is asymmetric here. Bare-shape Possible is the right baseline.)
        let pair = makePair(
            forwardName: "parse",
            forwardLabel: nil,
            reverseName: "format",
            reverseLabel: nil,
            forwardParam: "Token",
            forwardReturn: "String"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion?.score.tier == .possible)
        #expect(!(suggestion?.score.signals.contains { $0.kind == .directionLabel } ?? false))
    }

    @Test("V1.11.1 — curated inverse-pair name + direction label on one side still surfaces (Possible)")
    func curatedInversePairWithDirectionLabelStillSurfaces() {
        // Hypothetical: `parse(after:) × format(_:)` — curated inverse
        // pair name match (+10), type symmetry (+25), direction counter
        // (-10) = +25 → Possible. The user's explicit `parse/format`
        // naming preserves the suggestion above the boundary, exactly
        // matching the v1.11 plan's open-decision-#1 design intent.
        let pair = makePair(
            forwardName: "parse",
            forwardLabel: "after",
            reverseName: "format",
            reverseLabel: nil,
            forwardParam: "Token",
            forwardReturn: "String"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion?.score.total == 25)
        #expect(suggestion?.score.tier == .possible)
        #expect(suggestion?.score.signals.contains { $0.kind == .directionLabel } ?? false)
        #expect(suggestion?.score.signals.contains { $0.kind == .exactNameMatch } ?? false)
    }

    @Test("V1.11.1 — `transform(value:) ↔ untransform(value:)` (non-direction labels) still emits (Possible)")
    func nonDirectionLabelDoesNotSuppress() {
        let pair = makePair(
            forwardName: "transform",
            forwardLabel: "value",
            reverseName: "untransform",
            reverseLabel: "value",
            forwardParam: "Token",
            forwardReturn: "Bytes"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion?.score.total == 25)
        #expect(suggestion?.score.tier == .possible)
        #expect(!(suggestion?.score.signals.contains { $0.kind == .directionLabel } ?? false))
    }

    @Test("V1.11.1 — both nil labels → no direction counter")
    func nilLabelsDoNotSuppress() {
        let pair = makePair(
            forwardName: "transform",
            forwardLabel: nil,
            reverseName: "untransform",
            reverseLabel: nil,
            forwardParam: "Token",
            forwardReturn: "Bytes"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion?.score.total == 25)
        #expect(!(suggestion?.score.signals.contains { $0.kind == .directionLabel } ?? false))
    }

    // MARK: - Boundary cases

    @Test("V1.11.1 — direction label is case-sensitive (`After` does not suppress)")
    func caseSensitive() {
        // Curated set uses lowerCamelCase per Swift convention; non-
        // conforming labels don't trigger the counter.
        let pair = makePair(
            forwardName: "step",
            forwardLabel: "After",
            reverseName: "unstep",
            reverseLabel: "Before",
            forwardParam: "Token",
            forwardReturn: "Token"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion?.score.total == 25, "Mismatched case shouldn't trigger the counter")
    }

    @Test("V1.11.1 — counter weight is exactly -10")
    func counterWeightIsMinusTen() {
        // Cycle-9's round-trip arm should mirror this exactly; a
        // regression to -15 would push curated-name pairs into the
        // noisy +20 boundary zone.
        let pair = makePair(
            forwardName: "step",
            forwardLabel: "after",
            reverseName: "unstep",
            reverseLabel: nil,
            forwardParam: "Token",
            forwardReturn: "Token"
        )
        // The pair lands in Suppressed so .suggest returns nil; verify
        // the weight by introspecting via a curated-name pair instead.
        let curated = makePair(
            forwardName: "parse",
            forwardLabel: "after",
            reverseName: "format",
            reverseLabel: nil,
            forwardParam: "Token",
            forwardReturn: "String"
        )
        let suggestion = InversePairTemplate.suggest(for: curated)
        let directionSignal = suggestion?.score.signals.first(where: { $0.kind == .directionLabel })
        #expect(directionSignal?.weight == -10)
        // Sanity check: bare-shape with direction label should be
        // suppressed under the same -10 weight.
        #expect(InversePairTemplate.suggest(for: pair) == nil)
    }

    @Test("V1.11.1 — directionLabels reused from IdempotenceTemplate (open decision #2)")
    func reusesIdempotenceCuratedSet() {
        // v1.11 reuses the v1.10 curated set as-is rather than
        // duplicating. Hoisting to a shared namespace lands at v1.13
        // when round-trip becomes the third consumer.
        #expect(IdempotenceTemplate.directionLabels.count == 10)
        let expected: Set<String> = [
            "after", "before",
            "next", "prev", "previous",
            "advance", "succ", "pred", "successor", "predecessor"
        ]
        #expect(IdempotenceTemplate.directionLabels == expected)
    }

    // MARK: - Fixtures

    private func makePair(
        forwardName: String,
        forwardLabel: String? = nil,
        reverseName: String,
        reverseLabel: String? = nil,
        forwardParam: String,
        forwardReturn: String
    ) -> FunctionPair {
        let forward = FunctionSummary(
            name: forwardName,
            parameters: [Parameter(label: forwardLabel, internalName: "x", typeText: forwardParam, isInout: false)],
            returnTypeText: forwardReturn,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let reverse = FunctionSummary(
            name: reverseName,
            parameters: [Parameter(label: reverseLabel, internalName: "x", typeText: forwardReturn, isInout: false)],
            returnTypeText: forwardParam,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 5, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        return FunctionPair(forward: forward, reverse: reverse)
    }
}

@Suite("InversePairTemplate — V1.11.1 end-to-end discover() integration")
struct InversePairDirectionLabelDiscoverTests {

    @Test("V1.11.1 — `index(after:) ↔ index(before:)` no longer surfaces in discover() output")
    func indexAfterIndexBeforeSuppressedEndToEnd() {
        let indexAfter = makeSummary(
            name: "index",
            label: "after",
            paramType: "Index",
            returnType: "Index",
            line: 10
        )
        let indexBefore = makeSummary(
            name: "index",
            label: "before",
            paramType: "Index",
            returnType: "Index",
            line: 20
        )
        let suggestions = TemplateRegistry.discover(
            in: [indexAfter, indexBefore],
            typeDecls: []
        )
        let inversePairCount = suggestions.filter { $0.templateName == "inverse-pair" }.count
        #expect(inversePairCount == 0, "Direction-labeled inverse-pair should not surface")
    }

    @Test("V1.11.1 — non-direction-labeled inverse pair still surfaces")
    func nonDirectionPairStillSurfacesEndToEnd() {
        // `parse(_:) × format(_:)` shape on a non-Equatable carrier —
        // FunctionPairing classifies as inverse-pair candidate.
        let parse = makeSummary(
            name: "parse",
            label: nil,
            paramType: "MyToken",
            returnType: "String",
            line: 30
        )
        let format = makeSummary(
            name: "format",
            label: nil,
            paramType: "String",
            returnType: "MyToken",
            line: 40
        )
        let suggestions = TemplateRegistry.discover(
            in: [parse, format],
            typeDecls: []
        )
        let inversePair = suggestions.first { $0.templateName == "inverse-pair" }
        #expect(inversePair != nil, "Non-direction-labeled pair should still surface")
    }

    private func makeSummary(
        name: String,
        label: String?,
        paramType: String,
        returnType: String,
        line: Int
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: label, internalName: "x", typeText: paramType, isInout: false)],
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: line, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }
}
