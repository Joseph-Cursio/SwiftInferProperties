import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

/// V1.37.B — equivalence tests for the MonotonicityTemplate migration
/// to the Constraint Engine (PRD §20.2). Verifies that
/// `MonotonicityTemplate.suggest(for:vocabulary:)` (now Constraint-
/// orchestrated) produces bit-for-bit identical Suggestion output
/// regardless of how it's called (direct vs through the runner).
@Suite("MonotonicityTemplate — V1.37.B Constraint equivalence")
struct MonotonicityConstraintEquivalenceTests {

    // MARK: - Fixture corpus

    private static func fixtureCorpus() -> [(label: String, summary: FunctionSummary)] {
        let location = SourceLocation(file: "Test.swift", line: 1, column: 1)
        return [
            // Curated verb 'count' + Int codomain → accept, 25+10 = 35 Possible
            ("curatedVerb_count", FunctionSummary(
                name: "count",
                parameters: [
                    Parameter(label: nil, internalName: "items", typeText: "Foo", isInout: false)
                ],
                returnTypeText: "Int",
                isThrows: false, isAsync: false, isMutating: false, isStatic: false,
                location: location,
                containingTypeName: "Container",
                bodySignals: .empty
            )),
            // Curated suffix 'userCount' + Int codomain → accept, 25+10 = 35
            ("curatedSuffix_userCount", FunctionSummary(
                name: "userCount",
                parameters: [
                    Parameter(label: nil, internalName: "group", typeText: "Foo", isInout: false)
                ],
                returnTypeText: "Int",
                isThrows: false, isAsync: false, isMutating: false, isStatic: false,
                location: location,
                containingTypeName: "Container",
                bodySignals: .empty
            )),
            // Bare-shape no-name + curated codomain → accept (just type signal), 25 Possible
            ("bareShape", FunctionSummary(
                name: "someProjection",
                parameters: [
                    Parameter(label: nil, internalName: "x", typeText: "Foo", isInout: false)
                ],
                returnTypeText: "Double",
                isThrows: false, isAsync: false, isMutating: false, isStatic: false,
                location: location,
                containingTypeName: "Container",
                bodySignals: .empty
            )),
            // Non-curated codomain (Bool) → gate fails, nil
            ("nonComparableCodomain", FunctionSummary(
                name: "isFresh",
                parameters: [
                    Parameter(label: nil, internalName: "x", typeText: "Foo", isInout: false)
                ],
                returnTypeText: "Bool",
                isThrows: false, isAsync: false, isMutating: false, isStatic: false,
                location: location,
                containingTypeName: "Container",
                bodySignals: .empty
            )),
            // Multi-param → gate fails
            ("multiParam", FunctionSummary(
                name: "count",
                parameters: [
                    Parameter(label: nil, internalName: "x", typeText: "Foo", isInout: false),
                    Parameter(label: nil, internalName: "y", typeText: "Foo", isInout: false)
                ],
                returnTypeText: "Int",
                isThrows: false, isAsync: false, isMutating: false, isStatic: false,
                location: location,
                containingTypeName: "Container",
                bodySignals: .empty
            )),
            // Mutating → gate fails
            ("mutating", FunctionSummary(
                name: "count",
                parameters: [
                    Parameter(label: nil, internalName: "x", typeText: "Foo", isInout: false)
                ],
                returnTypeText: "Int",
                isThrows: false, isAsync: false, isMutating: true, isStatic: false,
                location: location,
                containingTypeName: "Container",
                bodySignals: .empty
            )),
            // Non-deterministic body → veto
            ("nonDeterministic", FunctionSummary(
                name: "count",
                parameters: [
                    Parameter(label: nil, internalName: "x", typeText: "Foo", isInout: false)
                ],
                returnTypeText: "Int",
                isThrows: false, isAsync: false, isMutating: false, isStatic: false,
                location: location,
                containingTypeName: "Container",
                bodySignals: BodySignals(
                    hasNonDeterministicCall: true,
                    hasSelfComposition: false,
                    nonDeterministicAPIsDetected: ["Date()"]
                )
            ))
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
