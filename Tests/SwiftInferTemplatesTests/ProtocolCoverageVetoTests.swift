import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// V1.5.2 — protocol-coverage veto tests for the three single-summary
// algebraic templates (idempotence / commutativity / associativity).
// Pair-shaped templates (identity-element / inverse-pair / round-trip)
// live in `ProtocolCoverageVetoPairTests.swift`; discover() end-to-end
// integration in `ProtocolCoverageVetoIntegrationTests.swift`.
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
            Parameter(label: nil, internalName: "b", typeText: typeText, isInout: false)
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

// MARK: - Idempotence

@Suite("ProtocolCoverageVeto — idempotence (V1.5.2)")
struct IdempotenceProtocolCoverageVetoTests {

    @Test("Idempotence on : SetAlgebra type vetoes (covers setIntersectionIdempotent)")
    func setAlgebraVetoesIdempotence() {
        let summary = makeUnaryOp(name: "intersect", typeText: "MySet")
        let result = IdempotenceTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("MySet", conformances: ["SetAlgebra"])
        )
        #expect(result == nil, "SetAlgebra coverage should suppress idempotence")
    }

    @Test("Idempotence on : Semilattice type vetoes (covers semilatticeIdempotence)")
    func semilatticeVetoesIdempotence() {
        let summary = makeUnaryOp(name: "merge", typeText: "Lattice")
        let result = IdempotenceTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("Lattice", conformances: ["Semilattice"])
        )
        #expect(result == nil)
    }

    @Test("Idempotence on type with no relevant conformance still surfaces")
    func customTypeWithoutConformanceSurfaces() throws {
        let summary = makeUnaryOp(name: "normalize", typeText: "Doc")
        let suggestion = try #require(IdempotenceTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("Doc", conformances: ["Hashable", "Sendable"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }

    @Test("Idempotence on : Numeric is NOT vetoed (Numeric covers no idempotence law)")
    func numericDoesNotVetoIdempotence() throws {
        let summary = makeUnaryOp(name: "normalize", typeText: "Int")
        let suggestion = try #require(IdempotenceTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("Int", conformances: ["Numeric"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }

    @Test("Idempotence falls through cleanly with empty inheritedTypesByName")
    func emptyIndexIsBackwardsCompat() throws {
        let summary = makeUnaryOp(name: "normalize", typeText: "String")
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }
}

// MARK: - Commutativity

@Suite("ProtocolCoverageVeto — commutativity (V1.5.2)")
struct CommutativityProtocolCoverageVetoTests {

    @Test("\"+\" on : AdditiveArithmetic type vetoes")
    func plusOnAdditiveArithmeticVetoes() {
        let summary = makeBinaryOp(name: "+", typeText: "Money")
        let result = CommutativityTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("Money", conformances: ["AdditiveArithmetic"])
        )
        #expect(result == nil)
    }

    @Test("\"+\" on : Numeric type vetoes (transitive AdditiveArithmetic coverage)")
    func plusOnNumericVetoes() {
        let summary = makeBinaryOp(name: "+", typeText: "BigInt")
        let result = CommutativityTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("BigInt", conformances: ["Numeric"])
        )
        #expect(result == nil)
    }

    @Test("\"*\" on : Numeric type vetoes")
    func timesOnNumericVetoes() {
        let summary = makeBinaryOp(name: "*", typeText: "BigInt")
        let result = CommutativityTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("BigInt", conformances: ["Numeric"])
        )
        #expect(result == nil)
    }

    @Test("\"union\" on : SetAlgebra type vetoes")
    func unionOnSetAlgebraVetoes() {
        let summary = makeBinaryOp(name: "union", typeText: "BitSet")
        let result = CommutativityTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("BitSet", conformances: ["SetAlgebra"])
        )
        #expect(result == nil)
    }

    @Test("User-named \"combine\" on : Numeric type does NOT veto (op-class fall-through)")
    func combineOnNumericDoesNotVeto() throws {
        // Critical false-positive guard: the user's `combine` function on
        // an Int-shaped Numeric type is NOT covered by Numeric's `+` /
        // `*` commutativity laws — the kit covers operators specifically.
        let summary = makeBinaryOp(name: "combine", typeText: "Int")
        let suggestion = try #require(CommutativityTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("Int", conformances: ["Numeric"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }

    @Test("\"+\" on type without : AdditiveArithmetic conformance does NOT veto")
    func plusOnPlainTypeDoesNotVeto() throws {
        let summary = makeBinaryOp(name: "+", typeText: "Vector")
        let suggestion = try #require(CommutativityTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("Vector", conformances: ["Equatable"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }

    @Test("Op-class candidates table — exhaustive cases")
    func opClassCandidatesTable() {
        #expect(CommutativityTemplate.commutativityCoverageCandidates(forOp: "+")
            == [.additiveCommutative])
        #expect(CommutativityTemplate.commutativityCoverageCandidates(forOp: "*")
            == [.multiplicativeCommutative])
        #expect(CommutativityTemplate.commutativityCoverageCandidates(forOp: "union")
            == [.setUnionCommutative])
        #expect(CommutativityTemplate.commutativityCoverageCandidates(forOp: "formUnion")
            == [.setUnionCommutative])
        #expect(CommutativityTemplate.commutativityCoverageCandidates(forOp: "combine").isEmpty)
        #expect(CommutativityTemplate.commutativityCoverageCandidates(forOp: "merge").isEmpty)
    }
}

// MARK: - Associativity

@Suite("ProtocolCoverageVeto — associativity (V1.5.2)")
struct AssociativityProtocolCoverageVetoTests {

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

    @Test("\"union\" on : SetAlgebra vetoes (setUnionAssociative)")
    func unionOnSetAlgebraVetoes() {
        let summary = makeBinaryOp(name: "union", typeText: "BitSet")
        let result = AssociativityTemplate.suggest(
            for: summary,
            inheritedTypesByName: makeInheritedIndex("BitSet", conformances: ["SetAlgebra"])
        )
        #expect(result == nil)
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
        #expect(AssociativityTemplate.associativityCoverageCandidates(forOp: "union")
            == [.setUnionAssociative])
        #expect(AssociativityTemplate.associativityCoverageCandidates(forOp: "formUnion")
            == [.setUnionAssociative])
        #expect(AssociativityTemplate.associativityCoverageCandidates(forOp: "concat").isEmpty)
    }
}
