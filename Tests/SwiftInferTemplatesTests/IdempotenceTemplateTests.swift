import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

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
        let summary = makeIdempotenceSummary(name: "sorted", paramType: "[Int]", returnType: "[Int]")
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

@Suite("IdempotenceTemplate — docstring corroboration (+15, corroborate-only)")
struct IdempotenceDocstringCorroborationTests {

    @Test("Docstring lifts a shape-only candidate Possible 30 -> Likely 45 (surfaces by default)")
    func docstringLiftsShapeOnlyToLikely() throws {
        // `refresh` is not a curated verb, so shape alone = 30 (Possible, hidden).
        let summary = makeIdempotenceSummary(
            name: "refresh",
            paramType: "State",
            returnType: "State",
            docComment: "Recomputes derived state. Calling it on already-current state is idempotent."
        )
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary))
        #expect(suggestion.score.total == 45)
        #expect(suggestion.score.tier == .likely)
        #expect(suggestion.score.tier.isVisibleByDefault)
    }

    @Test("Docstring lifts a curated-verb candidate Likely 70 -> Strong 85")
    func docstringLiftsCuratedToStrong() throws {
        let summary = makeIdempotenceSummary(
            name: "normalize",
            paramType: "String",
            returnType: "String",
            docComment: "Returns the canonical form of the input."
        )
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary))
        #expect(suggestion.score.total == 85)
        #expect(suggestion.score.tier == .strong)
    }

    @Test("A negated docstring does not corroborate — score stays 30")
    func negatedDocstringDoesNotBoost() throws {
        let summary = makeIdempotenceSummary(
            name: "advance",
            paramType: "State",
            returnType: "State",
            docComment: "Advances the cursor by one. This is not idempotent."
        )
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary))
        #expect(suggestion.score.total == 30)
        #expect(suggestion.score.tier == .possible)
    }

    @Test("A non-matching shape earns no candidate even with idempotence prose (corroborate-only)")
    func docstringAloneNeverSurfaces() {
        // `(A) -> B` is not the idempotence shape; the docstring must not conjure a law.
        let summary = makeIdempotenceSummary(
            name: "encode",
            paramType: "Model",
            returnType: "Data",
            docComment: "Encodes the model. The operation is idempotent."
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }

    @Test("The corroboration signal is rendered in the explainability block")
    func corroborationSignalRendered() throws {
        let summary = makeIdempotenceSummary(
            name: "process",
            paramType: "String",
            returnType: "String",
            docComment: "Idempotent cleanup pass."
        )
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary))
        let why = suggestion.explainability.whySuggested.joined(separator: "\n")
        #expect(why.contains("Docstring corroborates idempotence"))
        #expect(why.contains("idempotent"))
    }
}

// MARK: - Shared helpers

func makeIdempotenceSummary(
    name: String,
    paramType: String? = nil,
    parameters explicitParameters: [Parameter]? = nil,
    returnType: String?,
    isMutating: Bool = false,
    containingType: String? = nil,
    bodySignals: BodySignals = .empty,
    docComment: String? = nil,
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
        docComment: docComment
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
