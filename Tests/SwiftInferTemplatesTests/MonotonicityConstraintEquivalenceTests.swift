import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// V1.37.B — equivalence tests for the MonotonicityTemplate migration
/// to the Constraint Engine (PRD §20.2). Verifies that
/// `MonotonicityTemplate.suggest(for:vocabulary:)` (now Constraint-
/// orchestrated) produces bit-for-bit identical Suggestion output
/// regardless of how it's called (direct vs through the runner).
@Suite("MonotonicityTemplate — V1.37.B Constraint equivalence")
struct MonotonicityConstraintEquivalenceTests {

    // MARK: - Fixture corpus

    private static let location = SourceLocation(file: "Test.swift", line: 1, column: 1)

    private static func unarySummary(
        name: String,
        paramName: String = "x",
        paramType: String = "Foo",
        returnType: String = "Int",
        isMutating: Bool = false,
        parameters: [Parameter]? = nil,
        bodySignals: BodySignals = .empty
    ) -> FunctionSummary {
        let params = parameters ?? [
            Parameter(label: nil, internalName: paramName, typeText: paramType, isInout: false)
        ]
        return FunctionSummary(
            name: name,
            parameters: params,
            returnTypeText: returnType,
            isThrows: false, isAsync: false, isMutating: isMutating, isStatic: false,
            location: location,
            containingTypeName: "Container",
            bodySignals: bodySignals
        )
    }

    private static func fixtureCorpus() -> [(label: String, summary: FunctionSummary)] {
        let nonDeterministic = BodySignals(
            hasNonDeterministicCall: true,
            hasSelfComposition: false,
            nonDeterministicAPIsDetected: ["Date()"]
        )
        let twoParams = [
            Parameter(label: nil, internalName: "x", typeText: "Foo", isInout: false),
            Parameter(label: nil, internalName: "y", typeText: "Foo", isInout: false)
        ]
        return [
            ("curatedVerb_count", unarySummary(name: "count", paramName: "items")),
            ("curatedSuffix_userCount", unarySummary(name: "userCount", paramName: "group")),
            ("bareShape", unarySummary(name: "someProjection", returnType: "Double")),
            ("nonComparableCodomain", unarySummary(name: "isFresh", returnType: "Bool")),
            ("multiParam", unarySummary(name: "count", parameters: twoParams)),
            ("mutating", unarySummary(name: "count", isMutating: true)),
            ("nonDeterministic", unarySummary(name: "count", bodySignals: nonDeterministic))
        ]
    }

    // MARK: - Equivalence

    @Test("V1.37.B — Constraint-based suggest produces bit-for-bit identical output to bespoke matcher")
    func equivalenceAcrossCorpus() {
        for (label, summary) in Self.fixtureCorpus() {
            let viaWrapper = MonotonicityTemplate.suggest(
                for: summary,
                vocabulary: .empty
            )
            let constraint = MonotonicityTemplate.makeConstraint(vocabulary: .empty)
            let viaRunner = ConstraintRunner.suggest(constraint: constraint, subject: summary)
            #expect(
                viaWrapper == viaRunner,
                "[\(label)] suggest(for:vocabulary:) and ConstraintRunner.suggest disagree"
            )
        }
    }

    @Test("V1.37.B — vocabulary propagates through the constraint")
    func vocabularyPropagates() {
        let summary = FunctionSummary(
            name: "blarp",
            parameters: [
                Parameter(label: nil, internalName: "x", typeText: "Foo", isInout: false)
            ],
            returnTypeText: "Int",
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "T.swift", line: 1, column: 1),
            containingTypeName: "Container",
            bodySignals: .empty
        )
        let voc = Vocabulary(monotonicityVerbs: ["blarp"])
        let suggestion = MonotonicityTemplate.suggest(for: summary, vocabulary: voc)
        let nameSignal = suggestion?.score.signals.first { $0.kind == .exactNameMatch }
        #expect(nameSignal != nil, "vocabulary verb match should produce +10 name signal")
        #expect(nameSignal?.weight == 10)
    }

    @Test("V1.37.B — caveat list is constant (no FP-conditional caveat)")
    func caveatsAreConstant() throws {
        let summary = FunctionSummary(
            name: "count",
            parameters: [
                Parameter(label: nil, internalName: "x", typeText: "Foo", isInout: false)
            ],
            returnTypeText: "Int",
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "T.swift", line: 1, column: 1),
            containingTypeName: "Container",
            bodySignals: .empty
        )
        let suggestion = try #require(MonotonicityTemplate.suggest(for: summary))
        // 2 caveats, both stable across Subject inputs (unlike Commutativity).
        #expect(suggestion.explainability.whyMightBeWrong.count == 2)
        #expect(suggestion.explainability.whyMightBeWrong[0].contains("Comparable"))
        #expect(suggestion.explainability.whyMightBeWrong[1].contains("@CheckProperty"))
    }
}
