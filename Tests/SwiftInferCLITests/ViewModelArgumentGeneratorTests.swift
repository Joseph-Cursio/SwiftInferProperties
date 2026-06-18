import SwiftInferCLI
import Testing

/// PROTOTYPE — curated, deterministic candidate-value generation for a
/// view-model action's single parameter (the x-curried idempotence
/// verifier applies the action twice with each value).
@Suite("ViewModelArgumentGenerator (prototype)")
struct ViewModelArgumentGeneratorTests {

    @Test("curated scalar types generate literal candidate values")
    func curatedScalars() {
        #expect(ViewModelArgumentGenerator.candidateValuesExpression(for: "Bool") == "[true, false]")
        #expect(ViewModelArgumentGenerator.candidateValuesExpression(for: "Int") == "[0, 1, -1]")
        #expect(ViewModelArgumentGenerator.candidateValuesExpression(for: "String") == "[\"\", \"x\"]")
    }

    @Test("Optional wraps nil plus each base value, typed for nil inference")
    func optionalWrapsNil() {
        let expr = ViewModelArgumentGenerator.candidateValuesExpression(for: "Bool?")
        #expect(expr == "[nil, true, false] as [Bool?]")
    }

    @Test("UUID generates deterministic fixed values (not random UUID())")
    func uuidIsDeterministic() {
        let expr = ViewModelArgumentGenerator.candidateValuesExpression(for: "UUID")
        #expect(expr?.contains("UUID(uuidString:") == true)
        #expect(expr?.contains("UUID()") == false)
    }

    @Test("non-curated types are not generatable (gated out of verify)")
    func nonGeneratableGated() {
        #expect(ViewModelArgumentGenerator.candidateValuesExpression(for: "Color") == nil)
        #expect(ViewModelArgumentGenerator.candidateValuesExpression(for: "CustomPayload") == nil)
        #expect(!ViewModelArgumentGenerator.isGeneratable("Color"))
        #expect(ViewModelArgumentGenerator.isGeneratable("Int"))
    }
}
