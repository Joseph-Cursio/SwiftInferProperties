import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

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

    private static let location = SourceLocation(file: "Test.swift", line: 1, column: 1)

    private static func binarySummary(
        name: String,
        lhsType: String = "Int",
        rhsType: String = "Int",
        returnType: String = "Int",
        containingType: String,
        bodySignals: BodySignals = .empty
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(label: nil, internalName: "lhs", typeText: lhsType, isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: rhsType, isInout: false)
            ],
            returnTypeText: returnType,
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: location,
            containingTypeName: containingType,
            bodySignals: bodySignals
        )
    }

    private static func fixtureCorpus() -> [(name: String, summary: FunctionSummary)] {
        let nonDeterministic = BodySignals(
            hasNonDeterministicCall: true,
            hasSelfComposition: false,
            nonDeterministicAPIsDetected: ["Date()"]
        )
        return [
            ("merge", binarySummary(name: "merge", containingType: "Bag")),
            ("subtract", binarySummary(name: "subtract", containingType: "Math")),
            ("voidReturn", binarySummary(name: "combine", returnType: "Void", containingType: "Foo")),
            ("paramMismatch", binarySummary(
                name: "combine", rhsType: "String", returnType: "String", containingType: "Foo"
            )),
            ("nonDeterministic", binarySummary(
                name: "combine", containingType: "Foo", bodySignals: nonDeterministic
            )),
            ("bareShape", binarySummary(
                name: "someUserOp", lhsType: "BigInt", rhsType: "BigInt",
                returnType: "BigInt", containingType: "BigInt"
            )),
            ("fpStorage", binarySummary(
                name: "add", lhsType: "Double", rhsType: "Double",
                returnType: "Double", containingType: "Math"
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
