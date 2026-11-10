import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// MARK: - Commutativity

@Suite("AssumedKitCoverage — commutativity (V1.5.2)")
struct CommutativityAssumedKitCoverageTests {

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
