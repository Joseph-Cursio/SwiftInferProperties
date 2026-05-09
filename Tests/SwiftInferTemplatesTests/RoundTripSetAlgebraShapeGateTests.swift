import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

// V1.16.1 — SetAlgebra-shape veto on RoundTripTemplate.
// Closes post-v1.15 priority #1 (cycle-12 OC SetAlgebra round-trip
// survivors: 2 `intersection ↔ subtracting` Self-typed pairs that
// V1.14.1 deliberately scoped to inverse-pair only).
//
// Cycle-13 mechanism extension — replicates V1.14.1's function-name +
// type-shape composite mechanism on round-trip; consumes the V1.16.1-
// hoisted `SetAlgebraShape.isSelfTypedBinaryOp(_:)`.
//
// Score arithmetic for round-trip (baseline +30 typeSymmetry):
//   bare typeSymmetry           : +30  → Possible
//   bare + setAlgebra-veto      : +30 - 25 = +5  → Suppressed
//   curated encode/decode (+40) : +40 + 30 = +70 → Likely (no veto)
//   curated + setAlgebra-veto   : +70 - 25 = +45 → Likely (preserved
//                                                          if both fire,
//                                                          hypothetical)

@Suite("RoundTripTemplate — V1.16.1 SetAlgebra-shape veto")
struct RoundTripSetAlgebraShapeGateTests {

    // MARK: - Suppression cases (the cycle-12 OC survivor pattern)

    @Test("V1.16.1 — `intersection(_:) ↔ subtracting(_:)` Self-typed pair is suppressed")
    func intersectionSubtractingSelfPairSuppressed() {
        let pair = makePair(
            forwardName: "intersection",
            reverseName: "subtracting",
            paramType: "Self",
            returnType: "Self"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion == nil, "SetAlgebra-shape round-trip pair should be suppressed")
    }

    @Test(
        "V1.16.1 — all 16 curated × curated combinations suppress",
        arguments: ["union", "intersection", "symmetricDifference", "subtracting"],
                   ["union", "intersection", "symmetricDifference", "subtracting"]
    )
    func allCuratedCombinationsSuppress(forward: String, reverse: String) {
        let pair = makePair(
            forwardName: forward,
            reverseName: reverse,
            paramType: "Self",
            returnType: "Self"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion == nil, "\(forward) ↔ \(reverse) should suppress")
    }

    // MARK: - Non-suppression cases

    @Test("V1.16.1 — `encode(_:) ↔ decode(_:)` (curated names, non-Self typing) preserved as Likely")
    func curatedNamesNonSelfTypingPreserved() {
        let pair = makePair(
            forwardName: "encode",
            reverseName: "decode",
            paramType: "Token",
            returnType: "Data"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion != nil)
        let hasVeto = suggestion?.score.signals.contains { signal in
            signal.kind == .protocolCoveredProperty
                && signal.detail.contains("SetAlgebra-shape pair")
        } ?? false
        #expect(!hasVeto, "Non-curated names should not trigger SetAlgebra veto")
    }

    @Test("V1.16.1 — `intersection(_:) ↔ subtracting(_:)` on (Int) -> Int does NOT trigger veto")
    func curatedNameNonSelfTypingDoesNotTrigger() {
        let pair = makePair(
            forwardName: "intersection",
            reverseName: "subtracting",
            paramType: "Int",
            returnType: "Int"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        let hasVeto = suggestion?.score.signals.contains { signal in
            signal.kind == .protocolCoveredProperty
                && signal.detail.contains("SetAlgebra-shape pair")
        } ?? false
        #expect(!hasVeto, "Non-Self-typed pair should not trigger SetAlgebra veto")
    }

    @Test("V1.16.1 — one curated + one non-curated name does NOT trigger veto")
    func mixedCuratedNonCuratedDoesNotTrigger() {
        let pair = makePair(
            forwardName: "intersection",
            reverseName: "parse",
            paramType: "Self",
            returnType: "Self"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        let hasVeto = suggestion?.score.signals.contains { signal in
            signal.kind == .protocolCoveredProperty
                && signal.detail.contains("SetAlgebra-shape pair")
        } ?? false
        #expect(!hasVeto, "One-side match should not trigger SetAlgebra veto")
    }

    // MARK: - Boundary + composition cases

    @Test("V1.16.1 — veto weight is exactly -25 (uniform with V1.14.1 + V1.16.1 idempotence)")
    func vetoWeightIsMinusTwentyFive() {
        let pair = makePair(
            forwardName: "intersection",
            reverseName: "subtracting",
            paramType: "Self",
            returnType: "Self"
        )
        let signal = RoundTripTemplate.setAlgebraShapeVeto(for: pair)
        #expect(signal?.weight == -25)
        #expect(signal?.kind == .protocolCoveredProperty)
    }

    @Test("V1.16.1 — case-sensitive (`Intersection` does not trigger)")
    func caseSensitive() {
        let pair = makePair(
            forwardName: "Intersection",
            reverseName: "Subtracting",
            paramType: "Self",
            returnType: "Self"
        )
        let signal = RoundTripTemplate.setAlgebraShapeVeto(for: pair)
        #expect(signal == nil)
    }

    @Test("V1.16.1 — cross-type counter + SetAlgebra veto compose to deeper Suppressed")
    func crossTypeAndSetAlgebraCompose() {
        // typeSymmetry +30 + cross-type -25 + SetAlgebra -25 = -20
        // → deeply Suppressed.
        let pair = makeCrossTypePair(
            forwardName: "intersection",
            reverseName: "subtracting",
            paramType: "Self",
            returnType: "Self"
        )
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion == nil)
    }

    // MARK: - Fixtures

    private func makePair(
        forwardName: String,
        reverseName: String,
        paramType: String,
        returnType: String
    ) -> FunctionPair {
        let forward = makeSummary(
            name: forwardName, paramType: paramType, returnType: returnType,
            file: "Test.swift", line: 1
        )
        let reverse = makeSummary(
            name: reverseName, paramType: returnType, returnType: paramType,
            file: "Test.swift", line: 5
        )
        return FunctionPair(forward: forward, reverse: reverse)
    }

    private func makeCrossTypePair(
        forwardName: String,
        reverseName: String,
        paramType: String,
        returnType: String
    ) -> FunctionPair {
        let forward = makeSummary(
            name: forwardName, paramType: paramType, returnType: returnType,
            file: "A.swift", line: 1, containingType: "TypeA"
        )
        let reverse = makeSummary(
            name: reverseName, paramType: returnType, returnType: paramType,
            file: "B.swift", line: 5, containingType: "TypeB"
        )
        return FunctionPair(forward: forward, reverse: reverse)
    }

    private func makeSummary(
        name: String,
        paramType: String,
        returnType: String,
        file: String,
        line: Int,
        containingType: String? = nil
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "x", typeText: paramType, isInout: false)],
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: file, line: line, column: 1),
            containingTypeName: containingType,
            bodySignals: .empty
        )
    }
}

@Suite("RoundTripTemplate — V1.16.1 end-to-end discover() integration")
struct RoundTripSetAlgebraShapeDiscoverTests {

    @Test("V1.16.1 — `intersection(_:) ↔ subtracting(_:)` Self-pair no longer surfaces in discover()")
    func setAlgebraRoundTripSuppressedEndToEnd() {
        let intersection = makeSummary(name: "intersection", line: 10)
        let subtracting = makeSummary(name: "subtracting", line: 20)
        let suggestions = TemplateRegistry.discover(
            in: [intersection, subtracting],
            typeDecls: []
        )
        let roundTripCount = suggestions.filter { $0.templateName == "round-trip" }.count
        #expect(roundTripCount == 0, "SetAlgebra-shape round-trip pair should not surface")
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
