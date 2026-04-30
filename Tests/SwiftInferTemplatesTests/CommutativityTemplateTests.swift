import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

// swiftlint:disable type_body_length
// Test suites cohere around their subject — splitting along the 250-line
// body limit would scatter the commutativity-template assertions across
// multiple files for no reader benefit.
@Suite("CommutativityTemplate — type pattern, name match, anti-commutativity counter, vetoes")
struct CommutativityTemplateTests {

    // MARK: - Type pattern

    @Test("Two same-type params and matching return scores 30 (Possible) with no name signal")
    func typeShapeAlone() {
        let summary = makeSummary(
            name: "blend",
            paramTypes: ("Color", "Color"),
            returnType: "Color"
        )
        let suggestion = CommutativityTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 30)
        #expect(suggestion?.score.tier == .possible)
    }

    @Test("Curated commutativity verb on (T, T) -> T scores 70 (Likely)")
    func curatedVerbAdds40() {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set"
        )
        let suggestion = CommutativityTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
    }

    @Test("Single-parameter function never matches the commutativity pattern")
    func singleParamDoesNotMatch() {
        let summary = makeSummary(
            name: "merge",
            parameters: [Parameter(label: nil, internalName: "x", typeText: "Set", isInout: false)],
            returnType: "Set"
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Three-parameter function never matches the commutativity pattern")
    func threeParamDoesNotMatch() {
        let summary = makeSummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "Set", isInout: false),
                Parameter(label: nil, internalName: "b", typeText: "Set", isInout: false),
                Parameter(label: nil, internalName: "c", typeText: "Set", isInout: false)
            ],
            returnType: "Set"
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Mismatched parameter types do not match")
    func mismatchedParamTypesDoNotMatch() {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Set", "Array"),
            returnType: "Set"
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Return type that doesn't match params does not match")
    func mismatchedReturnTypeDoesNotMatch() {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Bool"
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("inout on either parameter disqualifies")
    func inoutDisqualifies() {
        let summary = makeSummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "Set", isInout: true),
                Parameter(label: nil, internalName: "b", typeText: "Set", isInout: false)
            ],
            returnType: "Set"
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("mutating disqualifies")
    func mutatingDisqualifies() {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set",
            isMutating: true
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Void return is rejected")
    func voidReturnRejected() {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Void", "Void"),
            returnType: "Void"
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    // MARK: - Anti-commutativity counter-signal

    @Test("Curated anti-commutativity verb collapses score to suppressed")
    func antiCommutativitySuppresses() {
        let summary = makeSummary(
            name: "concatenate",
            paramTypes: ("Array", "Array"),
            returnType: "Array"
        )
        // 30 type-symmetry + (-30) anti-commutativity = 0 → suppressed.
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Curated anti-commutativity for `subtract` suppresses")
    func subtractAntiCommutativitySuppresses() {
        let summary = makeSummary(
            name: "subtract",
            paramTypes: ("Vector", "Vector"),
            returnType: "Vector"
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Project-vocabulary anti-commutativity verb suppresses too")
    func projectVocabAntiCommutativitySuppresses() {
        let summary = makeSummary(
            name: "concatenateOrdered",
            paramTypes: ("Array", "Array"),
            returnType: "Array"
        )
        let vocabulary = Vocabulary(antiCommutativityVerbs: ["concatenateOrdered"])
        #expect(CommutativityTemplate.suggest(for: summary, vocabulary: vocabulary) == nil)
    }

    @Test("Anti-commutativity counter-signal renders with the project-vocab detail line")
    func projectVocabAntiCommutativityDetailLineIfVisible() throws {
        // Use the --include-possible threshold check separately — here
        // we construct a scenario where the score doesn't collapse so
        // we can read the rendered detail line: type-symmetry (+30)
        // plus a project-vocab COMMUTATIVITY verb (+40) plus a curated
        // anti-commutativity (-30) on a function whose name happens to
        // be in the project's commutativity list. Net: 40, Possible.
        // (Pathological but exercises the anti-commutativity code path.)
        let summary = makeSummary(
            name: "subtract",
            paramTypes: ("T", "T"),
            returnType: "T"
        )
        let vocabulary = Vocabulary(commutativityVerbs: ["subtract"])
        let suggestion = try #require(CommutativityTemplate.suggest(for: summary, vocabulary: vocabulary))
        // Score should be 30 + 40 - 30 = 40 → Possible.
        #expect(suggestion.score.total == 40)
        let counterLine = suggestion.explainability.whySuggested.first { line in
            line.contains("anti-commutativity")
        }
        #expect(counterLine == "Curated anti-commutativity verb match: 'subtract' (-30)")
    }

    // MARK: - Project vocabulary (commutativity verbs)

    @Test("Project-vocabulary verb on (T, T) -> T scores 70 (Likely)")
    func projectVocabularyVerb() {
        let summary = makeSummary(
            name: "unionGraphs",
            paramTypes: ("Graph", "Graph"),
            returnType: "Graph"
        )
        let vocabulary = Vocabulary(commutativityVerbs: ["unionGraphs"])
        let suggestion = CommutativityTemplate.suggest(for: summary, vocabulary: vocabulary)
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
    }

    @Test("Curated verb wins over project-vocabulary when both list the same name")
    func curatedTakesPrecedenceOverProjectVocabulary() throws {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set"
        )
        let vocabulary = Vocabulary(commutativityVerbs: ["merge"])
        let suggestion = try #require(CommutativityTemplate.suggest(for: summary, vocabulary: vocabulary))
        #expect(suggestion.score.total == 70)
        let nameLine = suggestion.explainability.whySuggested.first { line in
            line.contains("verb match")
        }
        #expect(nameLine == "Curated commutativity verb match: 'merge' (+40)")
    }

    @Test("Empty vocabulary leaves curated behaviour unchanged")
    func emptyVocabularyLeavesCuratedAlone() {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set"
        )
        let suggestion = CommutativityTemplate.suggest(for: summary, vocabulary: .empty)
        #expect(suggestion?.score.total == 70)
    }

    // MARK: - Vetoes

    @Test("Non-deterministic body veto suppresses regardless of name signal")
    func nonDeterministicVetoSuppresses() {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set",
            bodySignals: BodySignals(
                hasNonDeterministicCall: true,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: ["Date"]
            )
        )
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    // MARK: - Suggestion shape

    @Test("Suggestion carries the function as Evidence and uses 'commutativity' template ID")
    func evidenceCarriesFunctionMetadata() throws {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set"
        )
        let suggestion = try #require(CommutativityTemplate.suggest(for: summary))
        #expect(suggestion.templateName == "commutativity")
        let evidence = try #require(suggestion.evidence.first)
        #expect(evidence.displayName == "merge(_:_:)")
        #expect(evidence.signature == "(Set, Set) -> Set")
    }

    @Test("Generator and sampling are M1 placeholders (M3/M4 deferred)")
    func placeholderGeneratorAndSampling() throws {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set"
        )
        let suggestion = try #require(CommutativityTemplate.suggest(for: summary))
        #expect(suggestion.generator.source == .notYetComputed)
        #expect(suggestion.generator.confidence == nil)
        #expect(suggestion.generator.sampling == .notRun)
    }

    @Test("Equatable + class-equality caveats always populate the wrong-side block")
    func caveatsAlwaysPresent() throws {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set"
        )
        let suggestion = try #require(CommutativityTemplate.suggest(for: summary))
        #expect(suggestion.explainability.whyMightBeWrong.count == 2)
        #expect(suggestion.explainability.whyMightBeWrong[0].contains("Equatable"))
        #expect(suggestion.explainability.whyMightBeWrong[1].contains("class"))
    }

    // MARK: - Suggestion identity

    @Test("Suggestion identity is namespaced by the 'commutativity' template ID")
    func identityIncludesTemplateID() throws {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set"
        )
        let suggestion = try #require(CommutativityTemplate.suggest(for: summary))
        // Idempotence on the same signature would produce a different
        // identity because the template-ID prefix differs.
        let idempotenceIdentity = SuggestionIdentity(
            canonicalInput: "idempotence|" + IdempotenceTemplate.canonicalSignature(of: summary)
        )
        #expect(suggestion.identity != idempotenceIdentity)
    }

    // MARK: - Golden render

    @Test("Likely commutativity suggestion renders byte-for-byte against the M2 acceptance-bar golden")
    func likelyCommutativityGoldenRender() throws {
        let summary = FunctionSummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "lhs", typeText: "IntSet", isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: "IntSet", isInout: false)
            ],
            returnTypeText: "IntSet",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Sources/Demo/Sets.swift", line: 12, column: 5),
            containingTypeName: "IntSet",
            bodySignals: .empty
        )
        let suggestion = try #require(CommutativityTemplate.suggest(for: summary))
        let rendered = SuggestionRenderer.render(suggestion)
        let expected = """
[Suggestion]
Template: commutativity
Score:    70 (Likely)

Why suggested:
  ✓ merge(_:_:) (IntSet, IntSet) -> IntSet — Sources/Demo/Sets.swift:12
  ✓ Type-symmetry signature: (T, T) -> T (T = IntSet) (+30)
  ✓ Curated commutativity verb match: 'merge' (+40)

Why this might be wrong:
  ⚠ T must conform to Equatable for the emitted property to compile. \
SwiftInfer M1 does not verify protocol conformance — confirm before applying.
  ⚠ If T is a class with a custom ==, the property is over value equality as T.== defines it.

Generator: not yet computed (M3 prerequisite)
Sampling:  not run (M4 deferred)
Identity:  \(suggestion.identity.display)
Suppress:  // swiftinfer: skip \(suggestion.identity.display)
"""
        #expect(rendered == expected)
    }

    // MARK: - Helpers

    private func makeSummary(
        name: String,
        paramTypes: (String, String)? = nil,
        parameters explicitParameters: [Parameter]? = nil,
        returnType: String?,
        isMutating: Bool = false,
        bodySignals: BodySignals = .empty
    ) -> FunctionSummary {
        let parameters: [Parameter]
        if let explicitParameters {
            parameters = explicitParameters
        } else if let paramTypes {
            parameters = [
                Parameter(label: nil, internalName: "lhs", typeText: paramTypes.0, isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: paramTypes.1, isInout: false)
            ]
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
            paramTypes: nil,
            parameters: parameters,
            returnType: returnType,
            isMutating: false,
            bodySignals: .empty
        )
    }
}
// swiftlint:enable type_body_length
