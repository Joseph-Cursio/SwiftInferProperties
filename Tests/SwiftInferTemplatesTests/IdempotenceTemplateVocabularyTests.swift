import SwiftEffectInference
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// MARK: - Shared helpers

func makeIdempotenceSummary(
    name: String,
    returnType: String?,
    paramType: String? = nil,
    parameters explicitParameters: [Parameter]? = nil,
    isMutating: Bool = false,
    containingType: String? = nil,
    bodySignals: BodySignals = .empty,
    docComment: String? = nil,
    declaredEffect: Effect? = nil,
    declaresUnknownEffect: Bool = false,
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
        containingTypeName: containingType,
        bodySignals: bodySignals,
        declaresUnknownEffect: declaresUnknownEffect,
        docComment: docComment,
        declaredEffect: declaredEffect
    )
}

func makeIdempotenceSummary(
    name: String,
    parameters: [Parameter],
    returnType: String?
) -> FunctionSummary {
    makeIdempotenceSummary(
        name: name,
        returnType: returnType,
        paramType: nil,
        parameters: parameters,
        isMutating: false,
        bodySignals: .empty
    )
}

@Suite("IdempotenceTemplate — project vocabulary (PRD §4.5)")
struct IdempotenceTemplateVocabularyTests {

    @Test("Project-vocabulary verb on T -> T scores 70 (Likely)")
    func projectVocabularyVerb() {
        let summary = makeIdempotenceSummary(
            name: "sanitizeXML",
            returnType: "String",
            paramType: "String"
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
            returnType: "String",
            paramType: "String"
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
            returnType: "String",
            paramType: "String"
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
            returnType: "String",
            paramType: "String"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary, vocabulary: .empty)
        #expect(suggestion?.score.total == 70)
    }

    @Test("A name in neither list still produces the 30-baseline (Possible) suggestion")
    func unmatchedNameStillScoresBaseline() {
        let summary = makeIdempotenceSummary(
            name: "process",
            returnType: "String",
            paramType: "String"
        )
        let vocabulary = Vocabulary(idempotenceVerbs: ["sanitizeXML"])
        let suggestion = IdempotenceTemplate.suggest(for: summary, vocabulary: vocabulary)
        #expect(suggestion?.score.total == 30)
        #expect(suggestion?.score.tier == .possible)
    }

    // MARK: - B32 — instance self-form (`self -> Self`)

    @Test("B32 — an instance self-form idempotent transform matches and surfaces at Likely")
    func instanceSelfFormCuratedFires() {
        // `func normalized() -> Doc` on `Doc` — zero params, returns the
        // containing type. Was invisible (idempotence required 1 param); now
        // matches, like InvolutionTemplate's instance form.
        let summary = makeIdempotenceSummary(
            name: "normalized",
            returnType: "Doc",
            containingType: "Doc"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        let tier = suggestion?.score.tier
        #expect(tier == .likely || tier == .strong)
        #expect(suggestion?.explainability.whySuggested.contains { $0.contains("self -> Self") } == true)
    }

    @Test("B32 — a past-participle verb is curated (the non-mutating instance spelling)")
    func participleVerbIsCurated() {
        #expect(IdempotenceTemplate.curatedVerbs.contains("sorted"))
        #expect(IdempotenceTemplate.curatedVerbs.contains("normalized"))
        let summary = makeIdempotenceSummary(name: "sorted", returnType: "[Int]", paramType: "[Int]")
        #expect(IdempotenceTemplate.suggest(for: summary)?.score.tier == .likely)
    }

    @Test("B32 — an instance self-form with a non-curated name still surfaces at Possible")
    func instanceSelfFormBaselineIsPossible() {
        let summary = makeIdempotenceSummary(
            name: "rendered",
            returnType: "Widget",
            containingType: "Widget"
        )
        #expect(IdempotenceTemplate.suggest(for: summary)?.score.tier == .possible)
    }

    @Test("B32 — self -> OtherType is NOT matched (materialised/wrapper returns stay out of scope)")
    func instanceSelfFormRequiresContainerMatchesReturn() {
        let summary = makeIdempotenceSummary(
            name: "normalized",
            returnType: "OtherType",
            containingType: "Doc"
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }

    @Test("Self-return: a nullary instance method written `-> Self` matches the self-form")
    func instanceSelfFormAcceptsLiteralSelfReturn() {
        // `func canonicalized() -> Self` / `var canonicalizedTransform: Self` — the
        // literal `Self` is canonicalized to the container (as DualStylePairing /
        // SetAlgebraShape already do). A curated verb reaches Likely.
        let curated = makeIdempotenceSummary(
            name: "normalized",
            returnType: "Self",
            containingType: "Doc"
        )
        let suggestion = IdempotenceTemplate.suggest(for: curated)
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
        // A non-curated name still surfaces at Possible via the shape signal.
        let bare = makeIdempotenceSummary(
            name: "recompute",
            returnType: "Self",
            containingType: "Cache"
        )
        #expect(IdempotenceTemplate.suggest(for: bare)?.score.tier == .possible)
    }

    @Test("B32 — a mutating instance self-form is not a candidate")
    func mutatingInstanceSelfFormRejected() {
        let summary = makeIdempotenceSummary(
            name: "normalized",
            returnType: "Doc",
            isMutating: true,
            containingType: "Doc"
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }
}
