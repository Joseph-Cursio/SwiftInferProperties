import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// V1.5.2 — protocol-coverage veto tests for the three single-summary
// algebraic templates (idempotence / commutativity / associativity).
// Pair-shaped templates (identity-element / inverse-pair / round-trip)
// live in `AssumedKitCoveragePairTests.swift`; discover() end-to-end
// integration in `ProtocolCoverageDiscoverIntegrationTests.swift`.
//
// Each suite exercises positive-coverage suppression (kit law covers
// the candidate property → veto fires) + negative-coverage cases (no
// relevant conformance → veto skips) + op-class fall-through (op name
// doesn't bind to a kit-published law → veto skips).
//
// Mirrors `FloatingPointCounterSignalTests.swift`'s per-cycle posture:
// cycle-related test surface lives in dedicated files rather than
// across each template's existing test suite, so the cycle's
// empirical effect is easier to reason about.

// MARK: - Shared fixtures (top-level for cross-file reuse)

/// Build a single-arg summary `func op(_:T) -> T`. V1.5.2 fixture.
func makeUnaryOp(name: String, typeText: String) -> FunctionSummary {
    FunctionSummary(
        name: name,
        parameters: [Parameter(label: nil, internalName: "x", typeText: typeText, isInout: false)],
        returnTypeText: typeText,
        isThrows: false,
        isAsync: false,
        isMutating: false,
        isStatic: false,
        location: SourceLocation(file: "Test.swift", line: 1, column: 1),
        containingTypeName: nil,
        bodySignals: .empty
    )
}

/// Build a binary-op summary `func op(_:_:) -> T`. V1.5.2 fixture.
func makeBinaryOp(name: String, typeText: String) -> FunctionSummary {
    FunctionSummary(
        name: name,
        parameters: [
            Parameter(label: nil, internalName: "a", typeText: typeText, isInout: false),
            Parameter(label: nil, internalName: "b", typeText: typeText, isInout: false),
        ],
        returnTypeText: typeText,
        isThrows: false,
        isAsync: false,
        isMutating: false,
        isStatic: true,
        location: SourceLocation(file: "Test.swift", line: 1, column: 1),
        containingTypeName: typeText,
        bodySignals: .empty
    )
}

/// Build an `[String: Set<String>]` index from a single (type, conformances) entry.
func makeInheritedIndex(_ name: String, conformances: [String]) -> [String: Set<String>] {
    [name: Set(conformances)]
}

// MARK: - Associativity

@Suite("AssumedKitCoverage — associativity (V1.5.2)")
struct AssociativityAssumedKitCoverageTests {

    @Test("\"+\" on : AdditiveArithmetic vetoes (additiveAssociative)")
    func plusOnAdditiveArithmeticVetoes() {
        let summary = makeBinaryOp(name: "+", typeText: "Money")
        let result = AssociativityTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("Money", conformances: ["AdditiveArithmetic"])
        )
        #expect(result == nil)
    }

    @Test("\"*\" on : Numeric vetoes (multiplicativeAssociative)")
    func timesOnNumericVetoes() {
        let summary = makeBinaryOp(name: "*", typeText: "BigInt")
        let result = AssociativityTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("BigInt", conformances: ["Numeric"])
        )
        #expect(result == nil)
    }

    /// Inverted 2026-08-02. This test asserted `result == nil` — that associativity on
    /// `union` is suppressed because `checkSetAlgebraPropertyLaws` runs it. **It does not.**
    /// The kit ships fifteen SetAlgebra laws and no associativity law for any set operand
    /// (`grep -rn "unionAssociat"` in SwiftPropertyLaws: zero hits), so the veto suppressed
    /// a true, refutable law that nothing else checks — and this test ratified it.
    /// `docs/measurements/protocol-coverage-law-drift.md` §3.
    @Test("\"union\" on : SetAlgebra does NOT veto — the kit ships no set-associativity law")
    func unionOnSetAlgebraDoesNotVeto() throws {
        let summary = makeBinaryOp(name: "union", typeText: "BitSet")
        let suggestion = try #require(AssociativityTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("BitSet", conformances: ["SetAlgebra"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }

    @Test("\"intersection\" commutativity on : SetAlgebra vetoes — the kit DOES run it")
    func intersectionCommutativityOnSetAlgebraVetoes() {
        let summary = makeBinaryOp(name: "intersection", typeText: "BitSet")
        let result = CommutativityTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("BitSet", conformances: ["SetAlgebra"])
        )
        #expect(result == nil)
    }

    @Test("\"symmetricDifference\" commutativity on : SetAlgebra vetoes — the kit DOES run it")
    func symmetricDifferenceCommutativityOnSetAlgebraVetoes() {
        let summary = makeBinaryOp(name: "symmetricDifference", typeText: "BitSet")
        let result = CommutativityTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("BitSet", conformances: ["SetAlgebra"])
        )
        #expect(result == nil)
    }

    @Test("binary-idempotence on : SetAlgebra vetoes — the template had no veto until 2026-08-02")
    func binaryIdempotenceOnSetAlgebraVetoes() {
        for verb in ["union", "intersection"] {
            let summary = makeBinaryOp(name: verb, typeText: "BitSet")
            let result = BinaryIdempotenceTemplate.suggest(
                for: summary,
                inheritedTypesByName: makeInheritedIndex("BitSet", conformances: ["SetAlgebra"])
            )
            #expect(result == nil, "binary-idempotence on \(verb) should be kit-covered")
        }
    }

    @Test("User-named \"combine\" on : Numeric does NOT veto (op-class fall-through)")
    func combineOnNumericDoesNotVeto() throws {
        let summary = makeBinaryOp(name: "combine", typeText: "Int")
        let suggestion = try #require(AssociativityTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("Int", conformances: ["Numeric"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }

    @Test("Op-class candidates table — exhaustive cases")
    func opClassCandidatesTable() {
        #expect(AssociativityTemplate.associativityCoverageCandidates(forOp: "+")
            == [.additiveAssociative])
        #expect(AssociativityTemplate.associativityCoverageCandidates(forOp: "*")
            == [.multiplicativeAssociative])
        // The set verbs return NO candidate — the kit has no set-associativity law.
        #expect(AssociativityTemplate.associativityCoverageCandidates(forOp: "union").isEmpty)
        #expect(AssociativityTemplate.associativityCoverageCandidates(forOp: "formUnion").isEmpty)
        #expect(AssociativityTemplate.associativityCoverageCandidates(forOp: "intersection").isEmpty)
        #expect(AssociativityTemplate.associativityCoverageCandidates(forOp: "concat").isEmpty)
    }
}
