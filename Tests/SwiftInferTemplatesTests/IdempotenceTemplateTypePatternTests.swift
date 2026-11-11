import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("IdempotenceTemplate — type pattern")
struct IdempotenceTemplateTypePatternTests {

    @Test("Single param T -> T with no other signals scores 30 (Possible)")
    func typeSymmetryAlone() {
        let summary = makeIdempotenceSummary(
            name: "process",
            returnType: "String",
            paramType: "String"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 30)
        #expect(suggestion?.score.tier == .possible)
    }

    @Test("Curated verb on T -> T scores 70 (Likely)")
    func curatedVerbAdds40() {
        let summary = makeIdempotenceSummary(
            name: "normalize",
            returnType: "String",
            paramType: "String"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
    }

    @Test("Curated verb plus self-composition body signal scores 90 (Strong)")
    func curatedVerbPlusSelfComposition() {
        let summary = makeIdempotenceSummary(
            name: "normalize",
            returnType: "String",
            paramType: "String",
            bodySignals: BodySignals(
                hasNonDeterministicCall: false,
                hasSelfComposition: true,
                nonDeterministicAPIsDetected: []
            )
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 90)
        #expect(suggestion?.score.tier == .strong)
    }

    @Test("Multi-parameter functions never match the idempotence pattern")
    func multiParameterFunctionDoesNotMatch() {
        let summary = makeIdempotenceSummary(
            name: "normalize",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "String", isInout: false),
                Parameter(label: nil, internalName: "b", typeText: "String", isInout: false),
            ],
            returnType: "String"
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }

    @Test("Mismatched parameter and return types do not match")
    func mismatchedTypesDoNotMatch() {
        let summary = makeIdempotenceSummary(
            name: "normalize",
            returnType: "Int",
            paramType: "String"
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }

    @Test("inout parameter disqualifies the type-symmetry signal")
    func inoutDisqualifies() {
        let summary = makeIdempotenceSummary(
            name: "normalize",
            parameters: [Parameter(label: nil, internalName: "v", typeText: "String", isInout: true)],
            returnType: "String"
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }

    @Test("mutating disqualifies the type-symmetry signal")
    func mutatingDisqualifies() {
        let summary = makeIdempotenceSummary(
            name: "normalize",
            returnType: "String",
            paramType: "String",
            isMutating: true
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }

    @Test("Void return is rejected even though T == T textually")
    func voidReturnRejected() {
        let summary = makeIdempotenceSummary(
            name: "normalize",
            returnType: "Void",
            paramType: "Void"
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }

    @Test("Nil return type (implicit Void) is rejected")
    func implicitVoidReturnRejected() {
        let summary = makeIdempotenceSummary(
            name: "normalize",
            returnType: nil,
            paramType: "String"
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }
}
