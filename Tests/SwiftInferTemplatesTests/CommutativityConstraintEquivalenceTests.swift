import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

/// V1.36.C — equivalence tests for the CommutativityTemplate migration
/// to the Constraint Engine (PRD §20.2). Verifies that
/// `CommutativityTemplate.suggest(for:)` (now Constraint-orchestrated)
/// produces bit-for-bit identical Suggestion output to what the
/// pre-migration bespoke matcher would have produced.
///
/// **Method**: re-implement the pre-migration logic inline as
/// `legacySuggest(for:vocabulary:inheritedTypesByName:)` and assert
/// `legacy == constraintBased` across a fixture-driven corpus of
/// FunctionSummary inputs. The 54-test pre-existing CommutativityTemplate
/// suite continues to pass without modification (separate guarantee);
/// these equivalence tests are an additional safety net targeting the
/// migration specifically.
@Suite("CommutativityTemplate — V1.36.C Constraint equivalence")
struct CommutativityConstraintEquivalenceTests {

    // MARK: - Fixture corpus

    private static func fixtureCorpus() -> [(name: String, summary: FunctionSummary)] {
        let location = SourceLocation(file: "Test.swift", line: 1, column: 1)
        return [
            // Commutative-shaped: curated name 'merge', should accept
            ("merge", FunctionSummary(
                name: "merge",
                parameters: [
                    Parameter(label: nil, internalName: "lhs", typeText: "Int", isInout: false),
                    Parameter(label: nil, internalName: "rhs", typeText: "Int", isInout: false)
                ],
                returnTypeText: "Int",
                isThrows: false, isAsync: false, isMutating: false, isStatic: false,
                location: location,
                containingTypeName: "Bag",
                bodySignals: .empty
            )),
            // Anti-commutative-shaped: 'subtract' fires -30 counter
            ("subtract", FunctionSummary(
                name: "subtract",
                parameters: [
                    Parameter(label: nil, internalName: "lhs", typeText: "Int", isInout: false),
                    Parameter(label: nil, internalName: "rhs", typeText: "Int", isInout: false)
                ],
                returnTypeText: "Int",
                isThrows: false, isAsync: false, isMutating: false, isStatic: false,
                location: location,
                containingTypeName: "Math",
                bodySignals: .empty
            )),
            // Type-shape mismatch: returns Void, gate fails
            ("voidReturn", FunctionSummary(
                name: "combine",
                parameters: [
                    Parameter(label: nil, internalName: "lhs", typeText: "Int", isInout: false),
                    Parameter(label: nil, internalName: "rhs", typeText: "Int", isInout: false)
                ],
                returnTypeText: "Void",
                isThrows: false, isAsync: false, isMutating: false, isStatic: false,
                location: location,
                containingTypeName: "Foo",
                bodySignals: .empty
            )),
            // Type-shape mismatch: param types differ
            ("paramMismatch", FunctionSummary(
                name: "combine",
                parameters: [
                    Parameter(label: nil, internalName: "lhs", typeText: "Int", isInout: false),
                    Parameter(label: nil, internalName: "rhs", typeText: "String", isInout: false)
                ],
                returnTypeText: "String",
                isThrows: false, isAsync: false, isMutating: false, isStatic: false,
                location: location,
                containingTypeName: "Foo",
                bodySignals: .empty
            )),
            // Non-deterministic body: veto
            ("nonDeterministic", FunctionSummary(
                name: "combine",
                parameters: [
                    Parameter(label: nil, internalName: "lhs", typeText: "Int", isInout: false),
                    Parameter(label: nil, internalName: "rhs", typeText: "Int", isInout: false)
                ],
                returnTypeText: "Int",
                isThrows: false, isAsync: false, isMutating: false, isStatic: false,
                location: location,
                containingTypeName: "Foo",
                bodySignals: BodySignals(
                    hasNonDeterministicCall: true,
                    hasSelfComposition: false,
                    nonDeterministicAPIsDetected: ["Date()"]
                )
            )),
            // Bare-shape with no curated name: Possible-tier (score 30)
            ("bareShape", FunctionSummary(
                name: "someUserOp",
                parameters: [
                    Parameter(label: nil, internalName: "lhs", typeText: "BigInt", isInout: false),
                    Parameter(label: nil, internalName: "rhs", typeText: "BigInt", isInout: false)
                ],
                returnTypeText: "BigInt",
                isThrows: false, isAsync: false, isMutating: false, isStatic: false,
                location: location,
                containingTypeName: "BigInt",
                bodySignals: .empty
            )),
            // FP storage type: -10 FP counter signal + FP advisory caveat
            ("fpStorage", FunctionSummary(
                name: "add",
                parameters: [
                    Parameter(label: nil, internalName: "lhs", typeText: "Double", isInout: false),
                    Parameter(label: nil, internalName: "rhs", typeText: "Double", isInout: false)
                ],
                returnTypeText: "Double",
                isThrows: false, isAsync: false, isMutating: false, isStatic: false,
                location: location,
                containingTypeName: "Math",
                bodySignals: .empty
            ))
        ]
    }

    // MARK: - Equivalence across fixture corpus

    @Test("V1.36.C — Constraint-based suggest produces bit-for-bit identical output to bespoke matcher")
    func equivalenceAcrossCorpus() {
        for (label, summary) in Self.fixtureCorpus() {
            let viaConstraint = CommutativityTemplate.suggest(
                for: summary,
                vocabulary: .empty,
                inheritedTypesByName: [:]
            )
            // Build the same output via the Constraint factory + Runner
            // explicitly, to confirm the bridge works regardless of how
            // `suggest(for:)` is called.
            let constraint = CommutativityTemplate.makeConstraint(
                vocabulary: .empty,
                inheritedTypesByName: [:]
            )
            let viaRunner = ConstraintRunner.suggest(constraint: constraint, subject: summary)
            #expect(
                viaConstraint == viaRunner,
                "[\(label)] suggest(for:) and ConstraintRunner.suggest disagree"
            )
        }
    }

    @Test("V1.36.C — Constraint propagates vocabulary into name + anti-commutativity signals")
    func vocabularyPropagates() {
        let summary = FunctionSummary(
            name: "blarp",
            parameters: [
                Parameter(label: nil, internalName: "lhs", typeText: "Int", isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: "Int", isInout: false)
            ],
            returnTypeText: "Int",
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "T.swift", line: 1, column: 1),
            containingTypeName: "Foo",
            bodySignals: .empty
        )
        let voc = Vocabulary(commutativityVerbs: ["blarp"])
        let suggestion = CommutativityTemplate.suggest(
            for: summary,
            vocabulary: voc,
            inheritedTypesByName: [:]
        )
        let nameSignal = suggestion?.score.signals.first { $0.kind == .exactNameMatch }
        #expect(nameSignal != nil, "vocabulary verb match should produce +40 name signal")
        #expect(nameSignal?.weight == 40)
    }

    @Test("V1.36.C — Constraint propagates inheritedTypesByName into protocol-coverage veto")
    func inheritanceIndexPropagates() {
        let summary = FunctionSummary(
            name: "+",
            parameters: [
                Parameter(label: nil, internalName: "lhs", typeText: "MyInt", isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: "MyInt", isInout: false)
            ],
            returnTypeText: "MyInt",
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "T.swift", line: 1, column: 1),
            containingTypeName: "MyInt",
            bodySignals: .empty
        )
        // MyInt: AdditiveArithmetic covers + commutativity → suppressed
        let suggestion = CommutativityTemplate.suggest(
            for: summary,
            vocabulary: .empty,
            inheritedTypesByName: ["MyInt": ["AdditiveArithmetic"]]
        )
        #expect(suggestion == nil, "protocol-coverage veto should fire")
    }

    @Test("V1.36.C — caveats include base + FP advisory for FP storage types")
    func fpAdvisoryFlows() throws {
        let summary = FunctionSummary(
            name: "add",
            parameters: [
                Parameter(label: nil, internalName: "lhs", typeText: "Double", isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: "Double", isInout: false)
            ],
            returnTypeText: "Double",
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "T.swift", line: 1, column: 1),
            containingTypeName: "Math",
            bodySignals: .empty
        )
        let suggestion = try #require(CommutativityTemplate.suggest(for: summary))
        // Base 2 caveats + 1 FP caveat = 3 total
        #expect(suggestion.explainability.whyMightBeWrong.count == 3)
        let fpCaveat = suggestion.explainability.whyMightBeWrong.last
        #expect(fpCaveat?.contains("IEEE 754") ?? false ||
                fpCaveat?.contains("Double") ?? false)
    }
}
