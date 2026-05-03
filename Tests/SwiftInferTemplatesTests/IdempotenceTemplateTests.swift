import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("IdempotenceTemplate — type pattern")
struct IdempotenceTemplateTypePatternTests {

    @Test("Single param T -> T with no other signals scores 30 (Possible)")
    func typeSymmetryAlone() {
        let summary = makeIdempotenceSummary(
            name: "process",
            paramType: "String",
            returnType: "String"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 30)
        #expect(suggestion?.score.tier == .possible)
    }

    @Test("Curated verb on T -> T scores 70 (Likely)")
    func curatedVerbAdds40() {
        let summary = makeIdempotenceSummary(
            name: "normalize",
            paramType: "String",
            returnType: "String"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
    }

    @Test("Curated verb plus self-composition body signal scores 90 (Strong)")
    func curatedVerbPlusSelfComposition() {
        let summary = makeIdempotenceSummary(
            name: "normalize",
            paramType: "String",
            returnType: "String",
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
                Parameter(label: nil, internalName: "b", typeText: "String", isInout: false)
            ],
            returnType: "String"
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }

    @Test("Mismatched parameter and return types do not match")
    func mismatchedTypesDoNotMatch() {
        let summary = makeIdempotenceSummary(
            name: "normalize",
            paramType: "String",
            returnType: "Int"
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
            paramType: "String",
            returnType: "String",
            isMutating: true
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }

    @Test("Void return is rejected even though T == T textually")
    func voidReturnRejected() {
        let summary = makeIdempotenceSummary(
            name: "normalize",
            paramType: "Void",
            returnType: "Void"
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }

    @Test("Nil return type (implicit Void) is rejected")
    func implicitVoidReturnRejected() {
        let summary = makeIdempotenceSummary(
            name: "normalize",
            paramType: "String",
            returnType: nil
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }
}

@Suite("IdempotenceTemplate — project vocabulary (PRD §4.5)")
struct IdempotenceTemplateVocabularyTests {

    @Test("Project-vocabulary verb on T -> T scores 70 (Likely)")
    func projectVocabularyVerb() {
        let summary = makeIdempotenceSummary(
            name: "sanitizeXML",
            paramType: "String",
            returnType: "String"
        )
        let vocabulary = Vocabulary(idempotenceVerbs: ["sanitizeXML", "rewritePath"])
        let suggestion = IdempotenceTemplate.suggest(for: summary, vocabulary: vocabulary)
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
    }

    @Test("Project-vocabulary signal renders with the project-vocab detail line")
    func projectVocabularyDetailLine() throws {
        let summary = makeIdempotenceSummary(
            name: "sanitizeXML",
            paramType: "String",
            returnType: "String"
        )
        let vocabulary = Vocabulary(idempotenceVerbs: ["sanitizeXML"])
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary, vocabulary: vocabulary))
        let nameLine = suggestion.explainability.whySuggested.first { line in
            line.contains("verb match")
        }
        #expect(nameLine == "Project-vocabulary idempotence verb match: 'sanitizeXML' (+40)")
    }

    @Test("Curated verb wins over project-vocabulary when both list the same name")
    func curatedTakesPrecedenceOverProjectVocabulary() throws {
        let summary = makeIdempotenceSummary(
            name: "normalize",
            paramType: "String",
            returnType: "String"
        )
        let vocabulary = Vocabulary(idempotenceVerbs: ["normalize"])
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary, vocabulary: vocabulary))
        // Score should still be 70 — not double-counted to 110.
        #expect(suggestion.score.total == 70)
        let nameLine = suggestion.explainability.whySuggested.first { line in
            line.contains("verb match")
        }
        #expect(nameLine == "Curated idempotence verb match: 'normalize' (+40)")
    }

    @Test("Empty vocabulary leaves curated behaviour unchanged")
    func emptyVocabularyLeavesCuratedAlone() {
        let summary = makeIdempotenceSummary(
            name: "normalize",
            paramType: "String",
            returnType: "String"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary, vocabulary: .empty)
        #expect(suggestion?.score.total == 70)
    }

    @Test("A name in neither list still produces the 30-baseline (Possible) suggestion")
    func unmatchedNameStillScoresBaseline() {
        let summary = makeIdempotenceSummary(
            name: "process",
            paramType: "String",
            returnType: "String"
        )
        let vocabulary = Vocabulary(idempotenceVerbs: ["sanitizeXML"])
        let suggestion = IdempotenceTemplate.suggest(for: summary, vocabulary: vocabulary)
        #expect(suggestion?.score.total == 30)
        #expect(suggestion?.score.tier == .possible)
    }
}

// MARK: - Shared helpers

func makeIdempotenceSummary(
    name: String,
    paramType: String? = nil,
    parameters explicitParameters: [Parameter]? = nil,
    returnType: String?,
    isMutating: Bool = false,
    bodySignals: BodySignals = .empty,
    file: String = "Test.swift",
    line: Int = 1
) -> FunctionSummary {
    let parameters: [Parameter]
    if let explicitParameters {
        parameters = explicitParameters
    } else if let paramType {
        parameters = [Parameter(label: nil, internalName: "value", typeText: paramType, isInout: false)]
    } else {
        parameters = []
    }
    return FunctionSummary(
        name: name,
        parameters: parameters,
        returnTypeText: returnType,
        isThrows: false,
        isAsync: false,
        isMutating: isMutating,
        isStatic: false,
        location: SourceLocation(file: file, line: line, column: 1),
        containingTypeName: nil,
        bodySignals: bodySignals
    )
}

func makeIdempotenceSummary(
    name: String,
    parameters: [Parameter],
    returnType: String?
) -> FunctionSummary {
    makeIdempotenceSummary(
        name: name,
        paramType: nil,
        parameters: parameters,
        returnType: returnType,
        isMutating: false,
        bodySignals: .empty
    )
}
