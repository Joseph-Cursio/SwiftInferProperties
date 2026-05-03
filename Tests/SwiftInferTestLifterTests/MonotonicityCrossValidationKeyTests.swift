import SwiftInferCore
import SwiftInferTemplates
import Testing
@testable import SwiftInferTestLifter

@Suite("LiftedSuggestion.monotonicity — cross-validation-key parity (M5.0)")
struct MonotonicityCrossValidationKeyTests {

    @Test("LiftedSuggestion.monotonicity produces the (\"monotonicity\", [calleeName]) key")
    func factoryProducesExpectedKey() {
        let detection = DetectedMonotonicity(
            calleeName: "applyDiscount",
            leftArgName: "a",
            rightArgName: "b",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.monotonicity(from: detection)
        #expect(lifted.templateName == "monotonicity")
        #expect(lifted.crossValidationKey.templateName == "monotonicity")
        #expect(lifted.crossValidationKey.calleeNames == ["applyDiscount"])
        #expect(lifted.pattern == .monotonicity(detection))
    }

    /// Load-bearing M5.0 invariant: the LiftedSuggestion key matches
    /// the production-side `MonotonicityTemplate` key for the same
    /// callee. The +20 cross-validation signal lights up only when this
    /// equality holds.
    @Test("LiftedSuggestion.crossValidationKey matches MonotonicityTemplate's for the same callee")
    func liftedKeyMatchesTemplateEngineKey() throws {
        // Production-side: a (Widget) -> Int signature scores +25 from
        // ordered-codomain alone — Possible tier, but not suppressed,
        // so the suggestion appears in `discover` output.
        let calculate = FunctionSummary(
            name: "calculate",
            parameters: [Parameter(label: nil, internalName: "value", typeText: "Widget", isInout: false)],
            returnTypeText: "Int",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Pricing.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let suggestions = TemplateRegistry.discover(in: [calculate])
        let templateEngineMonotonicity = try #require(
            suggestions.first { $0.templateName == "monotonicity" }
        )
        let templateEngineKey = templateEngineMonotonicity.crossValidationKey

        let detection = DetectedMonotonicity(
            calleeName: "calculate",
            leftArgName: "a",
            rightArgName: "b",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.monotonicity(from: detection)

        #expect(lifted.crossValidationKey == templateEngineKey)
    }

    /// End-to-end Possible→Likely escalation per M5 plan acceptance (g):
    /// ordered-codomain alone scores 25 (Possible); +20 cross-validation
    /// pushes to 45 (Likely). The user-visible payoff for monotonicity's
    /// M5 wiring per Tier.swift:22 thresholds.
    @Test("End-to-end: monotonicity Possible→Likely escalation via TestLifter cross-validation")
    func endToEndPossibleToLikelyEscalation() throws {
        let calculate = FunctionSummary(
            name: "calculate",
            parameters: [Parameter(label: nil, internalName: "value", typeText: "Widget", isInout: false)],
            returnTypeText: "Int",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Pricing.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )

        let baseline = TemplateRegistry.discover(in: [calculate])
        let baselineMonotonicity = try #require(baseline.first { $0.templateName == "monotonicity" })
        let baselineTotal = baselineMonotonicity.score.total
        #expect(baselineMonotonicity.score.tier == .possible)

        let detection = DetectedMonotonicity(
            calleeName: "calculate",
            leftArgName: "a",
            rightArgName: "b",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.monotonicity(from: detection)
        let liftedKeys: Set<CrossValidationKey> = [lifted.crossValidationKey]

        let crossValidated = TemplateRegistry.discover(
            in: [calculate],
            crossValidationFromTestLifter: liftedKeys
        )
        let liftedMonotonicity = try #require(crossValidated.first { $0.templateName == "monotonicity" })
        #expect(liftedMonotonicity.score.total == baselineTotal + 20)
        #expect(liftedMonotonicity.score.tier == .likely)
        #expect(liftedMonotonicity.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
        #expect(
            liftedMonotonicity.explainability.whySuggested.contains { $0.contains("Cross-validated by TestLifter") }
        )
    }

    @Test("Mismatched callees produce different keys (no false +20)")
    func unrelatedKeysDoNotCollide() {
        let applyDiscountKey = LiftedSuggestion.monotonicity(from: DetectedMonotonicity(
            calleeName: "applyDiscount",
            leftArgName: "a",
            rightArgName: "b",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        let calculateKey = LiftedSuggestion.monotonicity(from: DetectedMonotonicity(
            calleeName: "calculate",
            leftArgName: "a",
            rightArgName: "b",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        #expect(applyDiscountKey != calculateKey)
    }

    @Test("Monotonicity key doesn't collide with idempotence/commutativity keys for the same name")
    func monotonicityDoesNotCollideAcrossTemplates() {
        let monotonicityKey = LiftedSuggestion.monotonicity(from: DetectedMonotonicity(
            calleeName: "process",
            leftArgName: "a",
            rightArgName: "b",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        let idempotenceKey = LiftedSuggestion.idempotence(from: DetectedIdempotence(
            calleeName: "process",
            inputBindingName: "x",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        let commutativityKey = LiftedSuggestion.commutativity(from: DetectedCommutativity(
            calleeName: "process",
            leftArgName: "a",
            rightArgName: "b",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        // Same callee name "process" doesn't collide because the
        // template name namespaces the key.
        #expect(monotonicityKey != idempotenceKey)
        #expect(monotonicityKey != commutativityKey)
    }
}
