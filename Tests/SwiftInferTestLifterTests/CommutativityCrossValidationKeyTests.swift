import SwiftInferCore
import SwiftInferTemplates
import Testing
@testable import SwiftInferTestLifter

@Suite("LiftedSuggestion.commutativity — cross-validation-key parity (M2.3)")
struct CommutativityCrossValidationKeyTests {

    @Test("LiftedSuggestion.commutativity produces the (\"commutativity\", [calleeName]) key")
    func factoryProducesExpectedKey() {
        let detection = DetectedCommutativity(
            calleeName: "merge",
            leftArgName: "a",
            rightArgName: "b",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.commutativity(from: detection)
        #expect(lifted.templateName == "commutativity")
        #expect(lifted.crossValidationKey.templateName == "commutativity")
        #expect(lifted.crossValidationKey.calleeNames == ["merge"])
        #expect(lifted.pattern == .commutativity(detection))
    }

    /// Load-bearing M2.3 invariant: a LiftedSuggestion derived from a
    /// test body's commutativity detection produces a CrossValidationKey
    /// byte-identical to the CrossValidationKey of TemplateEngine's
    /// CommutativityTemplate suggestion for the same callee. Mirror of
    /// the idempotence parity test.
    @Test("LiftedSuggestion.crossValidationKey matches CommutativityTemplate's for the same callee")
    func liftedKeyMatchesTemplateEngineKey() throws {
        // Production-side: build a function summary for `merge(_:_:)`
        // and run it through TemplateEngine's discover. `merge` is in
        // CommutativityTemplate.curatedVerbs so the suggestion fires.
        let merge = FunctionSummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "MyData", isInout: false),
                Parameter(label: nil, internalName: "b", typeText: "MyData", isInout: false)
            ],
            returnTypeText: "MyData",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Merger.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let suggestions = TemplateRegistry.discover(in: [merge])
        let templateEngineCommutativity = try #require(
            suggestions.first { $0.templateName == "commutativity" }
        )
        let templateEngineKey = templateEngineCommutativity.crossValidationKey

        let detection = DetectedCommutativity(
            calleeName: "merge",
            leftArgName: "a",
            rightArgName: "b",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.commutativity(from: detection)

        #expect(lifted.crossValidationKey == templateEngineKey)
    }

    @Test("End-to-end: LiftedSuggestion.commutativity's key feeds discover and lights up +20")
    func endToEndCrossValidationLightUp() throws {
        let merge = FunctionSummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "MyData", isInout: false),
                Parameter(label: nil, internalName: "b", typeText: "MyData", isInout: false)
            ],
            returnTypeText: "MyData",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Merger.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )

        let baseline = TemplateRegistry.discover(in: [merge])
        let baselineCommutativity = try #require(baseline.first { $0.templateName == "commutativity" })
        let baselineTotal = baselineCommutativity.score.total

        let detection = DetectedCommutativity(
            calleeName: "merge",
            leftArgName: "a",
            rightArgName: "b",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.commutativity(from: detection)
        let liftedKeys: Set<CrossValidationKey> = [lifted.crossValidationKey]

        let crossValidated = TemplateRegistry.discover(
            in: [merge],
            crossValidationFromTestLifter: liftedKeys
        )
        let liftedCommutativity = try #require(crossValidated.first { $0.templateName == "commutativity" })
        #expect(liftedCommutativity.score.total == baselineTotal + 20)
        #expect(liftedCommutativity.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
        #expect(
            liftedCommutativity.explainability.whySuggested.contains { $0.contains("Cross-validated by TestLifter") }
        )
    }

    @Test("Mismatched callees produce different keys (no false +20)")
    func unrelatedKeysDoNotCollide() {
        let mergeKey = LiftedSuggestion.commutativity(from: DetectedCommutativity(
            calleeName: "merge",
            leftArgName: "a",
            rightArgName: "b",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        let combineKey = LiftedSuggestion.commutativity(from: DetectedCommutativity(
            calleeName: "combine",
            leftArgName: "a",
            rightArgName: "b",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        #expect(mergeKey != combineKey)
    }

    @Test("Commutativity key doesn't collide with idempotence key for the same name")
    func commutativityDoesNotCollideWithIdempotence() {
        let commutativityKey = LiftedSuggestion.commutativity(from: DetectedCommutativity(
            calleeName: "merge",
            leftArgName: "a",
            rightArgName: "b",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        let idempotenceKey = LiftedSuggestion.idempotence(from: DetectedIdempotence(
            calleeName: "merge",
            inputBindingName: "x",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        // Same callee name "merge" wouldn't collide because the
        // template name namespaces the key.
        #expect(commutativityKey != idempotenceKey)
    }
}
