import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

// swiftlint:disable type_body_length file_length
// Test suites cohere around their subject — splitting along the 250-line
// body / 400-line file limit would scatter the idempotence-template
// assertions across multiple files for no reader benefit.
@Suite("IdempotenceTemplate — type pattern, name match, body signal, vetoes")
struct IdempotenceTemplateTests {

    // MARK: - Type pattern

    @Test("Single param T -> T with no other signals scores 30 (Possible)")
    func typeSymmetryAlone() {
        let summary = makeSummary(
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
        let summary = makeSummary(
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
        let summary = makeSummary(
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
        let summary = makeSummary(
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
        let summary = makeSummary(
            name: "normalize",
            paramType: "String",
            returnType: "Int"
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }

    @Test("inout parameter disqualifies the type-symmetry signal")
    func inoutDisqualifies() {
        let summary = makeSummary(
            name: "normalize",
            parameters: [Parameter(label: nil, internalName: "v", typeText: "String", isInout: true)],
            returnType: "String"
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }

    @Test("mutating disqualifies the type-symmetry signal")
    func mutatingDisqualifies() {
        let summary = makeSummary(
            name: "normalize",
            paramType: "String",
            returnType: "String",
            isMutating: true
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }

    @Test("Void return is rejected even though T == T textually")
    func voidReturnRejected() {
        let summary = makeSummary(
            name: "normalize",
            paramType: "Void",
            returnType: "Void"
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }

    @Test("Nil return type (implicit Void) is rejected")
    func implicitVoidReturnRejected() {
        let summary = makeSummary(
            name: "normalize",
            paramType: "String",
            returnType: nil
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }

    // MARK: - Project vocabulary (PRD §4.5)

    @Test("Project-vocabulary verb on T -> T scores 70 (Likely)")
    func projectVocabularyVerb() {
        let summary = makeSummary(
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
        let summary = makeSummary(
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
        let summary = makeSummary(
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
        let summary = makeSummary(
            name: "normalize",
            paramType: "String",
            returnType: "String"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary, vocabulary: .empty)
        #expect(suggestion?.score.total == 70)
    }

    @Test("A name in neither list still produces the 30-baseline (Possible) suggestion")
    func unmatchedNameStillScoresBaseline() {
        let summary = makeSummary(
            name: "process",
            paramType: "String",
            returnType: "String"
        )
        let vocabulary = Vocabulary(idempotenceVerbs: ["sanitizeXML"])
        let suggestion = IdempotenceTemplate.suggest(for: summary, vocabulary: vocabulary)
        #expect(suggestion?.score.total == 30)
        #expect(suggestion?.score.tier == .possible)
    }

    // MARK: - Vetoes

    @Test("Non-deterministic body veto suppresses the suggestion")
    func nonDeterministicBodyVetoes() {
        let summary = makeSummary(
            name: "normalize",
            paramType: "String",
            returnType: "String",
            bodySignals: BodySignals(
                hasNonDeterministicCall: true,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: ["Date"]
            )
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }

    @Test("Veto suppresses even when name + composition would have scored Strong")
    func vetoBeatsStrongScore() {
        let summary = makeSummary(
            name: "normalize",
            paramType: "String",
            returnType: "String",
            bodySignals: BodySignals(
                hasNonDeterministicCall: true,
                hasSelfComposition: true,
                nonDeterministicAPIsDetected: ["Date"]
            )
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }

    // MARK: - Suggestion shape

    @Test("Suggestion carries the function as Evidence")
    func evidenceCarriesFunctionMetadata() throws {
        let summary = makeSummary(
            name: "normalize",
            paramType: "String",
            returnType: "String"
        )
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary))
        #expect(suggestion.templateName == "idempotence")
        let evidence = try #require(suggestion.evidence.first)
        #expect(evidence.displayName == "normalize(_:)")
        #expect(evidence.signature == "(String) -> String")
        #expect(evidence.location.file == "Test.swift")
        #expect(evidence.location.line == 1)
    }

    @Test("Generator and sampling are M1 placeholders")
    func m1PlaceholderGenerator() throws {
        let summary = makeSummary(
            name: "normalize",
            paramType: "String",
            returnType: "String"
        )
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary))
        #expect(suggestion.generator.source == .notYetComputed)
        #expect(suggestion.generator.confidence == nil)
        #expect(suggestion.generator.sampling == .notRun)
    }

    @Test("Equatable + reference-equality caveats always populate the wrong-side block")
    func caveatsAlwaysPresent() throws {
        let summary = makeSummary(
            name: "normalize",
            paramType: "String",
            returnType: "String"
        )
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary))
        #expect(suggestion.explainability.whyMightBeWrong.count == 2)
        #expect(suggestion.explainability.whyMightBeWrong[0].contains("Equatable"))
        #expect(suggestion.explainability.whyMightBeWrong[1].contains("class"))
    }

    // MARK: - Golden render

    @Test("Project-vocabulary Likely suggestion renders byte-for-byte against the M2 acceptance-bar golden")
    func projectVocabularyGoldenRender() throws {
        // Closes M2 acceptance bar (a): proves a project-vocab idempotence
        // verb match contributes the same +40 weight as the curated list
        // and surfaces with the project-vocab detail line in the rendered
        // output. Mirror of RoundTripTemplateTests.projectVocabularyGoldenRender.
        let summary = FunctionSummary(
            name: "sanitizeXML",
            parameters: [Parameter(label: nil, internalName: "value", typeText: "String", isInout: false)],
            returnTypeText: "String",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Sources/Demo/Sanitizer.swift", line: 11, column: 5),
            containingTypeName: "Sanitizer",
            bodySignals: .empty
        )
        let vocabulary = Vocabulary(idempotenceVerbs: ["sanitizeXML"])
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary, vocabulary: vocabulary))
        let rendered = SuggestionRenderer.render(suggestion)
        let seedHex = SamplingSeed.renderHex(SamplingSeed.derive(from: suggestion.identity))
        let expected = """
[Suggestion]
Template: idempotence
Score:    70 (Likely)

Why suggested:
  ✓ sanitizeXML(_:) (String) -> String — Sources/Demo/Sanitizer.swift:11
  ✓ Type-symmetry signature: T -> T (T = String) (+30)
  ✓ Project-vocabulary idempotence verb match: 'sanitizeXML' (+40)

Why this might be wrong:
  ⚠ T must conform to Equatable for the emitted property to compile. \
SwiftInfer M1 does not verify protocol conformance — confirm before applying.
  ⚠ If T is a class with a custom ==, the property is over value equality as T.== defines it.

Generator: not yet computed (M3 prerequisite)
Sampling:  not run; lifted test seed: \(seedHex)
Identity:  \(suggestion.identity.display)
Suppress:  // swiftinfer: skip \(suggestion.identity.display)
"""
        #expect(rendered == expected)
    }

    @Test("Strong suggestion renders byte-for-byte against the M1 acceptance-bar golden")
    func strongSuggestionGoldenRender() throws {
        let summary = FunctionSummary(
            name: "normalize",
            parameters: [Parameter(label: nil, internalName: "value", typeText: "String", isInout: false)],
            returnTypeText: "String",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Sources/Demo/Sanitizer.swift", line: 7, column: 5),
            containingTypeName: "Sanitizer",
            bodySignals: BodySignals(
                hasNonDeterministicCall: false,
                hasSelfComposition: true,
                nonDeterministicAPIsDetected: []
            )
        )
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary))
        let rendered = SuggestionRenderer.render(suggestion)
        let seedHex = SamplingSeed.renderHex(SamplingSeed.derive(from: suggestion.identity))
        let expected = """
[Suggestion]
Template: idempotence
Score:    90 (Strong)

Why suggested:
  ✓ normalize(_:) (String) -> String — Sources/Demo/Sanitizer.swift:7
  ✓ Type-symmetry signature: T -> T (T = String) (+30)
  ✓ Curated idempotence verb match: 'normalize' (+40)
  ✓ Self-composition detected in body: normalize(normalize(x)) (+20)

Why this might be wrong:
  ⚠ T must conform to Equatable for the emitted property to compile. \
SwiftInfer M1 does not verify protocol conformance — confirm before applying.
  ⚠ If T is a class with a custom ==, the property is over value equality as T.== defines it.

Generator: not yet computed (M3 prerequisite)
Sampling:  not run; lifted test seed: \(seedHex)
Identity:  0xA1C9DEC1AEA2791C
Suppress:  // swiftinfer: skip 0xA1C9DEC1AEA2791C
"""
        #expect(rendered == expected)
    }

    // MARK: - Helpers

    private func makeSummary(
        name: String,
        paramType: String? = nil,
        parameters explicitParameters: [Parameter]? = nil,
        returnType: String?,
        isMutating: Bool = false,
        bodySignals: BodySignals = .empty
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
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: bodySignals
        )
    }

    private func makeSummary(
        name: String,
        parameters: [Parameter],
        returnType: String?
    ) -> FunctionSummary {
        makeSummary(
            name: name,
            paramType: nil,
            parameters: parameters,
            returnType: returnType,
            isMutating: false,
            bodySignals: .empty
        )
    }
}
// swiftlint:enable type_body_length
