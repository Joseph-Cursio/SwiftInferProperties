import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("IdempotenceTemplate — vetoes + suggestion shape")
struct IdempotenceTemplateBehaviorTests {

    // MARK: - Vetoes

    @Test("Non-deterministic body veto suppresses the suggestion")
    func nonDeterministicBodyVetoes() {
        let summary = makeIdempotenceSummary(
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
        let summary = makeIdempotenceSummary(
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
        let summary = makeIdempotenceSummary(
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
        let summary = makeIdempotenceSummary(
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
        let summary = makeIdempotenceSummary(
            name: "normalize",
            paramType: "String",
            returnType: "String"
        )
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary))
        #expect(suggestion.explainability.whyMightBeWrong.count == 2)
        #expect(suggestion.explainability.whyMightBeWrong[0].contains("Equatable"))
        #expect(suggestion.explainability.whyMightBeWrong[1].contains("class"))
    }
}

@Suite("IdempotenceTemplate — golden render")
struct IdempotenceTemplateGoldenTests {

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
}
