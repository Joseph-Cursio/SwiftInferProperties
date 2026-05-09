import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

// V1.14.1 — SetAlgebra-shape veto on InversePairTemplate.
// Closes post-v1.13 priority #1: 6 OC inverse-pair survivors with
// `intersection ↔ subtracting`-style Self-typed binary-op shape.
//
// First function-name + type-shape composite mechanism in the
// calibration loop, distinct from cycles 7-9's parameter-label-based
// class. Shape-only check (no protocol-conformance lookup) catches
// all 6 cycle-9 OC survivors; a conformance check would miss 4 of 6
// because OrderedSet doesn't declare `: SetAlgebra` directly (only
// has `Partial SetAlgebra` extensions).
//
// Score arithmetic for inverse-pair (baseline +25 typeSymmetry):
//   bare typeSymmetry           : +25  → Possible
//   bare + setAlgebra-veto      : +25 - 25 = 0  → Suppressed
//   curated name (+10)          : +25 + 10 = +35 → Possible (no veto)
//   curated name + veto         : +25 + 10 - 25 = +10 → Suppressed
//                                                       (still suppressed)

@Suite("InversePairTemplate — V1.14.1 SetAlgebra-shape veto")
struct InversePairSetAlgebraShapeGateTests {

    // MARK: - Suppression cases (the cycle-9 OC survivor pattern)

    @Test("V1.14.1 — `intersection(_:) ↔ subtracting(_:)` Self-typed pair is suppressed")
    func intersectionSubtractingSelfPairSuppressed() {
        // The textbook cycle-6 picks #45-#47 / cycle-9 OC survivor case.
        // Score: typeSymmetry +25, SetAlgebra veto -25 = 0 → Suppressed.
        let pair = makePair(
            forwardName: "intersection",
            reverseName: "subtracting",
            forwardParam: "Self",
            forwardReturn: "Self"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion == nil, "SetAlgebra-shape pair should be suppressed")
    }

    @Test("V1.14.1 — `intersection(_:) ↔ intersection(_:)` cross-file self-pair is suppressed")
    func intersectionSelfPairSuppressed() {
        // Cross-file self-pair shape: same `intersection(_:)` declared
        // on different conforming types (e.g., OrderedSet's Partial
        // SetAlgebra extension × OrderedSet.UnorderedView).
        let pair = makePair(
            forwardName: "intersection",
            reverseName: "intersection",
            forwardParam: "Self",
            forwardReturn: "Self"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion == nil)
    }

    @Test(
        "V1.14.1 — all 16 curated × curated combinations suppress",
        arguments: ["union", "intersection", "symmetricDifference", "subtracting"],
                   ["union", "intersection", "symmetricDifference", "subtracting"]
    )
    func allCuratedCombinationsSuppress(forward: String, reverse: String) {
        let pair = makePair(
            forwardName: forward,
            reverseName: reverse,
            forwardParam: "Self",
            forwardReturn: "Self"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion == nil, "\(forward) ↔ \(reverse) should suppress")
    }

    // MARK: - Non-suppression cases

    @Test("V1.14.1 — `parse(_:) ↔ format(_:)` (curated names, non-Self typing) still emits Possible")
    func curatedNameNonSelfTypingStillEmits() {
        // Existing V1.4.3 / V1.5.2 / V1.10.1 / V1.11.1 behavior preserved:
        // names not in SetAlgebra set + non-Self typing means the veto
        // doesn't fire; bare typeSymmetry +25 + curated/project name +10
        // = +35 → Possible.
        let pair = makePair(
            forwardName: "parse",
            reverseName: "format",
            forwardParam: "Token",
            forwardReturn: "String"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion != nil)
        #expect(suggestion?.score.tier == .possible)
        let hasVeto = suggestion?.score.signals.contains { signal in
            signal.kind == .protocolCoveredProperty && signal.weight == -25
        } ?? false
        #expect(!hasVeto, "Non-curated names should not trigger SetAlgebra veto")
    }

    @Test("V1.14.1 — `intersection(_:) ↔ subtracting(_:)` on non-Self type does NOT trigger veto")
    func curatedNameNonSelfTypingDoesNotTrigger() {
        // Same SetAlgebra-shape names but on (Int) -> Int — not the
        // protocol-extension Self shape. The veto requires both shape
        // AND name to match; this only matches name. (Hypothetical;
        // unusual to see SetAlgebra-named methods on non-Self types
        // in practice, but the gate must be tight.)
        let pair = makePair(
            forwardName: "intersection",
            reverseName: "subtracting",
            forwardParam: "Int",
            forwardReturn: "Int"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        let hasVeto = suggestion?.score.signals.contains { signal in
            signal.kind == .protocolCoveredProperty && signal.weight == -25
        } ?? false
        #expect(!hasVeto, "Non-Self-typed pair should not trigger SetAlgebra veto")
    }

    @Test("V1.14.1 — `intersection(_:) ↔ parse(_:)` (one curated, one non-curated) does NOT trigger veto")
    func mixedCuratedNonCuratedDoesNotTrigger() {
        // Both names must be in the curated set. One-side match doesn't
        // fire — preserves recall on legitimate cross-domain pairs.
        let pair = makePair(
            forwardName: "intersection",
            reverseName: "parse",
            forwardParam: "Self",
            forwardReturn: "Self"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        let hasVeto = suggestion?.score.signals.contains { signal in
            signal.kind == .protocolCoveredProperty && signal.weight == -25
        } ?? false
        #expect(!hasVeto, "One-side match should not trigger SetAlgebra veto")
    }

    @Test("V1.14.1 — Self-typed but non-curated names doesn't trigger")
    func nonCuratedSelfTypedNamesDoNotTrigger() {
        // Custom non-SetAlgebra `Self -> Self` binary ops should still
        // surface as inverse-pair candidates (e.g., a custom domain
        // `apply(_:) ↔ unapply(_:)` shape).
        let pair = makePair(
            forwardName: "apply",
            reverseName: "unapply",
            forwardParam: "Self",
            forwardReturn: "Self"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion != nil, "Non-SetAlgebra Self-typed pair should still surface")
        let hasVeto = suggestion?.score.signals.contains { signal in
            signal.kind == .protocolCoveredProperty && signal.weight == -25
        } ?? false
        #expect(!hasVeto)
    }

    // MARK: - Boundary + design cases

    @Test("V1.14.1 — case-sensitive (`Intersection` does not trigger veto)")
    func caseSensitive() {
        let pair = makePair(
            forwardName: "Intersection",
            reverseName: "Subtracting",
            forwardParam: "Self",
            forwardReturn: "Self"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        let hasVeto = suggestion?.score.signals.contains { signal in
            signal.kind == .protocolCoveredProperty && signal.weight == -25
        } ?? false
        #expect(!hasVeto, "Case-mismatched names should not trigger SetAlgebra veto")
    }

    @Test("V1.14.1 — veto weight is exactly -25")
    func vetoWeightIsMinusTwentyFive() {
        // Pin the calibrated weight; regression to vetoWeight or a
        // different number would change the curated-name interaction
        // arithmetic per the V1.14.0 plan's open decision #1.
        let pair = makePair(
            forwardName: "intersection",
            reverseName: "subtracting",
            forwardParam: "Self",
            forwardReturn: "Self"
        )
        // Bare-shape suppresses, so introspect via a curated-named pair
        // where the suggestion still emits with the veto signal attached.
        let curated = makePair(
            forwardName: "intersection",
            reverseName: "subtracting",
            forwardParam: "Self",
            forwardReturn: "Self"
        )
        // Both are the same shape; the test verifies the weight directly
        // via the helper's static method — bare-pair exercise above
        // confirms the score-collapse behavior end-to-end.
        let signal = InversePairTemplate.setAlgebraShapeVeto(for: curated)
        #expect(signal?.weight == -25)
        #expect(signal?.kind == .protocolCoveredProperty)
        // Sanity check: bare SetAlgebra-shape pair suppresses.
        #expect(InversePairTemplate.suggest(for: pair) == nil)
    }

    @Test("V1.14.1 — SetAlgebraShape.binaryOps lives in SwiftInferCore (canonical from cycle 1)")
    func setAlgebraShapeLivesInCore() {
        // V1.14.1 lands the curated set directly at
        // SwiftInferCore.SetAlgebraShape.binaryOps without a per-template
        // intermediate, applying the v1.13 hoist lesson preemptively.
        #expect(SetAlgebraShape.binaryOps.count == 4)
        let expected: Set<String> = [
            "union", "intersection", "symmetricDifference", "subtracting"
        ]
        #expect(SetAlgebraShape.binaryOps == expected)
    }

    @Test("V1.14.1 — direction-label counter + SetAlgebra veto are mutually exclusive in practice")
    func directionLabelAndSetAlgebraDontDoubleCount() {
        // SetAlgebra ops use `_:` (no label) parameters per Swift API
        // conventions, so the V1.11.1 direction-label counter and the
        // V1.14.1 SetAlgebra veto don't both fire on the same pair.
        // Confirm via a synthetic case: SetAlgebra-shape pair with
        // direction-labeled first param (very unusual). Both signals
        // should fire; the score should be even more suppressed.
        let pair = makePair(
            forwardName: "intersection",
            forwardLabel: "after",
            reverseName: "subtracting",
            reverseLabel: "before",
            forwardParam: "Self",
            forwardReturn: "Self"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        // typeSymmetry +25, direction -10, setAlgebra -25 = -10
        // → deeply Suppressed. Either signal alone would suffice.
        #expect(suggestion == nil)
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

@Suite("InversePairTemplate — V1.14.1 end-to-end discover() integration")
struct InversePairSetAlgebraShapeDiscoverTests {

    @Test("V1.14.1 — `intersection(_:) ↔ subtracting(_:)` Self-pair no longer surfaces in discover()")
    func intersectionSubtractingSuppressedEndToEnd() {
        let intersection = makeSummary(name: "intersection", line: 10)
        let subtracting = makeSummary(name: "subtracting", line: 20)
        let suggestions = TemplateRegistry.discover(
            in: [intersection, subtracting],
            typeDecls: []
        )
        let inversePairCount = suggestions.filter { $0.templateName == "inverse-pair" }.count
        #expect(inversePairCount == 0, "SetAlgebra-shape pair should not surface")
    }

    @Test("V1.14.1 — non-SetAlgebra Self-pair still surfaces")
    func nonSetAlgebraSelfPairStillSurfaces() {
        // Custom domain ops on Self-typed carrier: `apply ↔ unapply`
        // — not in SetAlgebra curated set, should still surface.
        let apply = makeSummary(name: "apply", line: 30)
        let unapply = makeSummary(name: "unapply", line: 40)
        let suggestions = TemplateRegistry.discover(
            in: [apply, unapply],
            typeDecls: []
        )
        let inversePair = suggestions.first { $0.templateName == "inverse-pair" }
        #expect(inversePair != nil, "Non-SetAlgebra Self-pair should still surface")
    }

    private func makeSummary(name: String, line: Int) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "other", typeText: "Self", isInout: false)],
            returnTypeText: "Self",
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
