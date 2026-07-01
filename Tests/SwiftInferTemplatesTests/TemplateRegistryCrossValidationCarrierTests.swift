import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Regression: the cross-validation / counter-signal rebuilds append a Signal
/// and must otherwise leave the Suggestion intact. They previously copied only
/// templateName/evidence/score/generator/explainability/identity, silently
/// resetting `carrier`, `carrierTypeName`, `liftedOrigin`, and `mockGenerator`
/// to nil — so any cross-validated suggestion lost its owner + generator carrier
/// before reaching the index/verify.
@Suite("TemplateRegistry cross-validation — carrier/origin preservation")
struct TemplateRegistryCrossValidationCarrierTests {

    /// A type-symmetric idempotence pick carries both `carrier` (the owner
    /// `Engine`) and `carrierTypeName` (the generator domain `String`).
    private func carrierSuggestion() -> Suggestion {
        let summary = FunctionSummary(
            name: "normalize",
            parameters: [Parameter(label: nil, internalName: "x", typeText: "String", isInout: false)],
            returnTypeText: "String",
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "T.swift", line: 1, column: 1),
            containingTypeName: "Engine",
            bodySignals: .empty
        )
        guard let suggestion = IdempotenceTemplate.suggest(for: summary) else {
            fatalError("IdempotenceTemplate must produce a suggestion for String -> String")
        }
        return suggestion
    }

    @Test("applyCrossValidation preserves carrier + carrierTypeName")
    func crossValidationPreservesCarrier() throws {
        let sug = carrierSuggestion()
        #expect(sug.carrier == "Engine")
        #expect(sug.carrierTypeName == "String")
        let result = TemplateRegistry.applyCrossValidation(to: [sug], matching: [sug.crossValidationKey])
        let rebuilt = try #require(result.first)
        #expect(rebuilt.score.total > sug.score.total)  // +20 applied → this is the rebuilt path
        #expect(rebuilt.carrier == "Engine")
        #expect(rebuilt.carrierTypeName == "String")
    }

    @Test("applyCounterSignal preserves carrier + carrierTypeName")
    func counterSignalPreservesCarrier() throws {
        let sug = carrierSuggestion()
        let result = TemplateRegistry.applyCounterSignal(to: [sug], matching: [sug.crossValidationKey])
        let rebuilt = try #require(result.first)
        #expect(rebuilt.carrier == "Engine")
        #expect(rebuilt.carrierTypeName == "String")
    }
}
