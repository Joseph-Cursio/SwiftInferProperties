import SwiftInferCore
import SwiftInferTemplates
import Testing
@testable import SwiftInferTestLifter

@Suite("LiftedSuggestion.countInvariance — cross-validation-key parity (M5.0)")
struct CountInvarianceCrossValidationKeyTests {

    @Test("LiftedSuggestion.countInvariance produces the (\"invariant-preservation\", [calleeName]) key")
    func factoryProducesExpectedKey() {
        let detection = DetectedCountInvariance(
            calleeName: "filter",
            inputBindingName: "xs",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.countInvariance(from: detection)
        #expect(lifted.templateName == "invariant-preservation")
        #expect(lifted.crossValidationKey.templateName == "invariant-preservation")
        #expect(lifted.crossValidationKey.calleeNames == ["filter"])
        #expect(lifted.pattern == .countInvariance(detection))
    }

    /// Load-bearing M5.0 invariant: the LiftedSuggestion key matches
    /// the production-side `InvariantPreservationTemplate` key for the
    /// same callee — but only when the user has annotated the function
    /// with `@CheckProperty(.preservesInvariant(\.count))`. Without the
    /// annotation, no production-side suggestion exists; M5 plan OD #1
    /// (a) handles that case via lifted-only stream entry.
    @Test("LiftedSuggestion.crossValidationKey matches InvariantPreservationTemplate's for annotated callee")
    func liftedKeyMatchesTemplateEngineKey() throws {
        // Production-side: needs `invariantKeypath` set on the
        // FunctionSummary; that's the macro-expansion equivalent of the
        // `@CheckProperty(.preservesInvariant(\.count))` annotation.
        let normalize = FunctionSummary(
            name: "filter",
            parameters: [Parameter(label: nil, internalName: "xs", typeText: "[Int]", isInout: false)],
            returnTypeText: "[Int]",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Filter.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty,
            invariantKeypath: "\\.count"
        )
        let suggestions = TemplateRegistry.discover(in: [normalize])
        let templateEngineInvariantPreservation = try #require(
            suggestions.first { $0.templateName == "invariant-preservation" }
        )
        let templateEngineKey = templateEngineInvariantPreservation.crossValidationKey

        let detection = DetectedCountInvariance(
            calleeName: "filter",
            inputBindingName: "xs",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.countInvariance(from: detection)

        #expect(lifted.crossValidationKey == templateEngineKey)
    }

    /// End-to-end +20 cross-validation when both production and lifted
    /// fire for the same annotated callee. Mirrors M2.4's idempotence /
    /// commutativity end-to-end test.
    @Test("End-to-end: countInvariance key feeds discover and lights up +20 (annotated case)")
    func endToEndCrossValidationLightUp() throws {
        let filter = FunctionSummary(
            name: "filter",
            parameters: [Parameter(label: nil, internalName: "xs", typeText: "[Int]", isInout: false)],
            returnTypeText: "[Int]",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Filter.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty,
            invariantKeypath: "\\.count"
        )

        let baseline = TemplateRegistry.discover(in: [filter])
        let baselineSuggestion = try #require(baseline.first { $0.templateName == "invariant-preservation" })
        let baselineTotal = baselineSuggestion.score.total

        let detection = DetectedCountInvariance(
            calleeName: "filter",
            inputBindingName: "xs",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.countInvariance(from: detection)
        let liftedKeys: Set<CrossValidationKey> = [lifted.crossValidationKey]

        let crossValidated = TemplateRegistry.discover(
            in: [filter],
            crossValidationFromTestLifter: liftedKeys
        )
        let liftedSuggestion = try #require(crossValidated.first { $0.templateName == "invariant-preservation" })
        #expect(liftedSuggestion.score.total == baselineTotal + 20)
        #expect(liftedSuggestion.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
        #expect(
            liftedSuggestion.explainability.whySuggested.contains { $0.contains("Cross-validated by TestLifter") }
        )
    }

    @Test("Mismatched callees produce different keys (no false +20)")
    func unrelatedKeysDoNotCollide() {
        let filterKey = LiftedSuggestion.countInvariance(from: DetectedCountInvariance(
            calleeName: "filter",
            inputBindingName: "xs",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        let mapKey = LiftedSuggestion.countInvariance(from: DetectedCountInvariance(
            calleeName: "map",
            inputBindingName: "xs",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        #expect(filterKey != mapKey)
    }

    @Test("CountInvariance key doesn't collide with idempotence key for the same name")
    func countInvarianceDoesNotCollideAcrossTemplates() {
        let countInvarianceKey = LiftedSuggestion.countInvariance(from: DetectedCountInvariance(
            calleeName: "transform",
            inputBindingName: "xs",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        let idempotenceKey = LiftedSuggestion.idempotence(from: DetectedIdempotence(
            calleeName: "transform",
            inputBindingName: "x",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        // Same callee name "transform" doesn't collide because the
        // template name namespaces the key.
        #expect(countInvarianceKey != idempotenceKey)
    }
}
