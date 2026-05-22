import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// V1.16.1 — SetAlgebra-shape veto on IdempotenceTemplate.
// Closes post-v1.15 priority #1 (cycle-12 OC SetAlgebra idempotence
// survivors: 4 `intersection`/`subtracting` (Self)->Self claims that
// V1.14.1 deliberately scoped to inverse-pair only).
//
// Cycle-13 mechanism extension — replicates V1.14.1's function-name +
// type-shape composite mechanism on idempotence; consumes the V1.16.1-
// hoisted `SetAlgebraShape.isSelfTypedBinaryOp(_:)`.
//
// Score arithmetic for idempotence (baseline +30 typeSymmetry):
//   bare typeSymmetry           : +30  → Possible
//   bare + setAlgebra-veto      : +30 - 25 = +5  → Suppressed
//   curated verb (+40)          : +40 + 30 = +70 → Likely
//   curated + setAlgebra-veto   : +70 - 25 = +45 → Likely (preserved
//                                                          if both fire,
//                                                          hypothetical)

@Suite("IdempotenceTemplate — V1.16.1 SetAlgebra-shape veto")
struct IdempotenceSetAlgebraShapeGateTests {

    // MARK: - Suppression cases (the cycle-12 OC survivor pattern)

    @Test("V1.16.1 — `intersection(_:)` (Self) -> Self is suppressed")
    func intersectionSelfIsSuppressed() {
        let summary = makeSummary(name: "intersection", paramType: "Self", returnType: "Self")
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion == nil, "SetAlgebra-shape idempotence should be suppressed")
    }

    @Test(
        "V1.16.1 — all 4 curated names suppress",
        arguments: ["union", "intersection", "symmetricDifference", "subtracting"]
    )
    func allCuratedNamesSuppress(name: String) {
        let summary = makeSummary(name: name, paramType: "Self", returnType: "Self")
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion == nil, "\(name) (Self) -> Self should suppress")
    }

    // MARK: - Non-suppression cases

    @Test("V1.16.1 — `normalize(_:)` (curated verb, non-Self typing) preserved as Likely")
    func curatedVerbNonSelfTypingPreserved() {
        let summary = makeSummary(name: "normalize", paramType: "String", returnType: "String")
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion?.score.tier == .likely)
        let hasVeto = suggestion?.score.signals.contains { signal in
            signal.kind == .protocolCoveredProperty
                && signal.detail.contains("SetAlgebra-shape function")
        } ?? false
        #expect(!hasVeto)
    }

    @Test("V1.16.1 — `intersection(_:)` on (Int) -> Int does NOT trigger veto")
    func curatedNameNonSelfTypingDoesNotTrigger() {
        let summary = makeSummary(name: "intersection", paramType: "Int", returnType: "Int")
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        let hasVeto = suggestion?.score.signals.contains { signal in
            signal.kind == .protocolCoveredProperty
                && signal.detail.contains("SetAlgebra-shape function")
        } ?? false
        #expect(!hasVeto, "Non-Self-typed function should not trigger SetAlgebra veto")
    }

    @Test("V1.16.1 — non-curated name on (Self) -> Self does NOT trigger veto")
    func nonCuratedSelfTypedDoesNotTrigger() {
        // Custom `Self -> Self` ops should still surface as idempotence
        // candidates.
        let summary = makeSummary(name: "apply", paramType: "Self", returnType: "Self")
        let signal = IdempotenceTemplate.setAlgebraShapeVeto(for: summary)
        #expect(signal == nil, "Non-SetAlgebra Self-typed op should not trigger veto")
    }

    // MARK: - Boundary cases

    @Test("V1.16.1 — veto weight is exactly -25 (uniform with V1.14.1 + V1.16.1 round-trip)")
    func vetoWeightIsMinusTwentyFive() {
        let summary = makeSummary(name: "intersection", paramType: "Self", returnType: "Self")
        let signal = IdempotenceTemplate.setAlgebraShapeVeto(for: summary)
        #expect(signal?.weight == -25)
        #expect(signal?.kind == .protocolCoveredProperty)
    }

    @Test("V1.16.1 — case-sensitive (`Intersection` does not trigger)")
    func caseSensitive() {
        let summary = makeSummary(name: "Intersection", paramType: "Self", returnType: "Self")
        let signal = IdempotenceTemplate.setAlgebraShapeVeto(for: summary)
        #expect(signal == nil)
    }

    // MARK: - Fixtures

    private func makeSummary(name: String, paramType: String, returnType: String) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "other", typeText: paramType, isInout: false)],
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

@Suite("IdempotenceTemplate — V1.16.1 end-to-end discover() integration")
struct IdempotenceSetAlgebraShapeDiscoverTests {

    @Test("V1.16.1 — `intersection(_:)` (Self) -> Self no longer surfaces idempotence in discover()")
    func setAlgebraIdempotenceSuppressedEndToEnd() {
        let intersection = FunctionSummary(
            name: "intersection",
            parameters: [Parameter(label: nil, internalName: "other", typeText: "Self", isInout: false)],
            returnTypeText: "Self",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let suggestions = TemplateRegistry.discover(in: [intersection], typeDecls: [])
        let idempotenceCount = suggestions.filter { $0.templateName == "idempotence" }.count
        #expect(idempotenceCount == 0, "SetAlgebra-shape idempotence should not surface")
    }
}
