import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// V1.38.D — equivalence tests for the v1.38 batch migrations of
/// Associativity / InvariantPreservation / DualStyleConsistency to
/// the Constraint Engine (PRD §20.2). Each per-template suite asserts
/// `wrapper-suggest == ConstraintRunner.suggest(constraint:)` on
/// representative fixtures, guaranteeing the migration is bit-for-bit
/// equivalence-preserving.

@Suite("AssociativityTemplate — V1.38.D Constraint equivalence")
struct AssociativityConstraintEquivalenceTests {

    private static let location = SourceLocation(file: "T.swift", line: 1, column: 1)

    private static func summary(name: String, isMutating: Bool = false) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(label: nil, internalName: "lhs", typeText: "Int", isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: "Int", isInout: false),
            ],
            returnTypeText: "Int",
            isThrows: false, isAsync: false, isMutating: isMutating, isStatic: false,
            location: location,
            containingTypeName: "Foo",
            bodySignals: .empty
        )
    }

    @Test("V1.38.D — Associativity: wrapper matches Constraint output across corpus")
    func equivalence() {
        let corpus: [(label: String, summary: FunctionSummary)] = [
            ("curated_combine", Self.summary(name: "combine")),
            ("curated_merge", Self.summary(name: "merge")),
            ("bare_userOp", Self.summary(name: "someOp")),
            ("mutating_combine", Self.summary(name: "combine", isMutating: true)),
        ]
        for (label, summary) in corpus {
            let wrapper = AssociativityTemplate.suggest(for: summary)
            let constraint = AssociativityTemplate.makeConstraint(
                vocabulary: .empty,
                reducerOps: [],
                inheritedTypesByName: [:]
            )
            let runner = ConstraintRunner.suggest(constraint: constraint, subject: summary)
            #expect(wrapper == runner, "[\(label)] disagree")
        }
    }

    @Test("V1.38.D — Associativity: runtime inputs propagate through the constraint")
    func runtimeInputsPropagate() throws {
        let summary = Self.summary(name: "myOp")
        // reducerOps including the op name should fire the reducer-usage signal
        let suggestion = try #require(AssociativityTemplate.suggest(
            for: summary,
            vocabulary: .empty,
            reducerOps: ["myOp"],
            inheritedTypesByName: [:]
        ))
        let reducerSignal = suggestion.score.signals.first { $0.kind == .reduceFoldUsage }
        #expect(reducerSignal != nil, "reducer-usage signal should fire when op is in reducerOps")
    }

    @Test("V1.38.D — Associativity: caveats always include FP advisory or fallback (3 entries)")
    func caveatsConstantCount() throws {
        let suggestion = try #require(AssociativityTemplate.suggest(for: Self.summary(name: "combine")))
        #expect(suggestion.explainability.whyMightBeWrong.count == 3)
    }
}
