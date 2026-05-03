import SwiftInferCore
import SwiftInferTemplates
import Testing
@testable import SwiftInferTestLifter

@Suite("LiftedSuggestion.reduceEquivalence — cross-validation-key parity (M5.0)")
struct AssociativityCrossValidationKeyTests {

    @Test("LiftedSuggestion.reduceEquivalence produces the (\"associativity\", [opCalleeName]) key")
    func factoryProducesExpectedKey() {
        let detection = DetectedReduceEquivalence(
            opCalleeName: "combine",
            seedSource: ".zero",
            collectionBindingName: "items",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.reduceEquivalence(from: detection)
        #expect(lifted.templateName == "associativity")
        #expect(lifted.crossValidationKey.templateName == "associativity")
        #expect(lifted.crossValidationKey.calleeNames == ["combine"])
        #expect(lifted.pattern == .reduceEquivalence(detection))
    }

    /// Load-bearing M5.0 invariant: the LiftedSuggestion key matches
    /// the production-side `AssociativityTemplate` key for the same
    /// op callee. The +20 cross-validation signal lights up only when
    /// this equality holds.
    @Test("LiftedSuggestion.crossValidationKey matches AssociativityTemplate's for the same op")
    func liftedKeyMatchesTemplateEngineKey() throws {
        // Production-side: a (T, T) -> T signature scores from
        // typeShape (+30). Plus +40 if name matches a curated verb in
        // commutativityVerbs (associativity reuses the same vocab key).
        // "combine" is in the curated list per AssociativityTemplate
        // type-doc.
        let combine = FunctionSummary(
            name: "combine",
            parameters: [
                Parameter(label: nil, internalName: "lhs", typeText: "Money", isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: "Money", isInout: false)
            ],
            returnTypeText: "Money",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Money.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let suggestions = TemplateRegistry.discover(in: [combine])
        let templateEngineAssociativity = try #require(
            suggestions.first { $0.templateName == "associativity" }
        )
        let templateEngineKey = templateEngineAssociativity.crossValidationKey

        let detection = DetectedReduceEquivalence(
            opCalleeName: "combine",
            seedSource: ".zero",
            collectionBindingName: "items",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.reduceEquivalence(from: detection)

        #expect(lifted.crossValidationKey == templateEngineKey)
    }

    @Test("End-to-end: reduceEquivalence key feeds discover and lights up +20")
    func endToEndCrossValidationLightUp() throws {
        let combine = FunctionSummary(
            name: "combine",
            parameters: [
                Parameter(label: nil, internalName: "lhs", typeText: "Money", isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: "Money", isInout: false)
            ],
            returnTypeText: "Money",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Money.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )

        let baseline = TemplateRegistry.discover(in: [combine])
        let baselineAssociativity = try #require(baseline.first { $0.templateName == "associativity" })
        let baselineTotal = baselineAssociativity.score.total

        let detection = DetectedReduceEquivalence(
            opCalleeName: "combine",
            seedSource: ".zero",
            collectionBindingName: "items",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.reduceEquivalence(from: detection)
        let liftedKeys: Set<CrossValidationKey> = [lifted.crossValidationKey]

        let crossValidated = TemplateRegistry.discover(
            in: [combine],
            crossValidationFromTestLifter: liftedKeys
        )
        let liftedAssociativity = try #require(crossValidated.first { $0.templateName == "associativity" })
        #expect(liftedAssociativity.score.total == baselineTotal + 20)
        #expect(liftedAssociativity.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
        #expect(
            liftedAssociativity.explainability.whySuggested.contains { $0.contains("Cross-validated by TestLifter") }
        )
    }

    @Test("Mismatched ops produce different keys (no false +20)")
    func unrelatedKeysDoNotCollide() {
        let combineKey = LiftedSuggestion.reduceEquivalence(from: DetectedReduceEquivalence(
            opCalleeName: "combine",
            seedSource: ".zero",
            collectionBindingName: "items",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        let plusKey = LiftedSuggestion.reduceEquivalence(from: DetectedReduceEquivalence(
            opCalleeName: "+",
            seedSource: "0",
            collectionBindingName: "xs",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        #expect(combineKey != plusKey)
    }

    @Test("Reduce-equivalence (associativity) key doesn't collide with commutativity for the same op")
    func associativityDoesNotCollideWithCommutativity() {
        let associativityKey = LiftedSuggestion.reduceEquivalence(from: DetectedReduceEquivalence(
            opCalleeName: "merge",
            seedSource: ".empty",
            collectionBindingName: "xs",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        let commutativityKey = LiftedSuggestion.commutativity(from: DetectedCommutativity(
            calleeName: "merge",
            leftArgName: "a",
            rightArgName: "b",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        // Same op name "merge" doesn't collide because the template
        // name namespaces the key.
        #expect(associativityKey != commutativityKey)
    }
}
