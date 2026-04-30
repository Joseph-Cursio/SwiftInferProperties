import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

// swiftlint:disable type_body_length file_length
// Test suites cohere around their subject — splitting along the 250-line
// body / 400-line file limit would scatter the associativity-template
// assertions across multiple files for no reader benefit.
@Suite("AssociativityTemplate — type pattern, name match, reducer/fold usage, vetoes")
struct AssociativityTemplateTests {

    // MARK: - Type pattern

    @Test("Two same-type params and matching return scores 30 (Possible) with no name signal")
    func typeShapeAlone() {
        let summary = makeSummary(
            name: "blend",
            paramTypes: ("Color", "Color"),
            returnType: "Color"
        )
        let suggestion = AssociativityTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 30)
        #expect(suggestion?.score.tier == .possible)
    }

    @Test("Curated commutativity verb on (T, T) -> T scores 70 (Likely) under associativity too")
    func curatedVerbAdds40() {
        // Per v0.2 §5.2 "Name signals: same as commutativity. Often
        // suggested alongside." — associativity reuses the commutativity
        // curated list with no dedicated `associativityVerbs` vocab key.
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set"
        )
        let suggestion = AssociativityTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
    }

    @Test("Single-parameter function never matches the associativity pattern")
    func singleParamDoesNotMatch() {
        let summary = makeSummary(
            name: "merge",
            parameters: [Parameter(label: nil, internalName: "x", typeText: "Set", isInout: false)],
            returnType: "Set"
        )
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Three-parameter function never matches the associativity pattern")
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
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Mismatched parameter types do not match")
    func mismatchedParamTypesDoNotMatch() {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Set", "Array"),
            returnType: "Set"
        )
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Return type that doesn't match params does not match")
    func mismatchedReturnTypeDoesNotMatch() {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Bool"
        )
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
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
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }

    @Test("mutating disqualifies")
    func mutatingDisqualifies() {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set",
            isMutating: true
        )
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Void return is rejected")
    func voidReturnRejected() {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Void", "Void"),
            returnType: "Void"
        )
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }

    // MARK: - Anti-commutativity verbs are NOT counter-signals here

    @Test("Anti-commutativity verb does NOT suppress associativity (concat is associative)")
    func antiCommutativityDoesNotSuppressAssociativity() throws {
        // `concatenate` IS in commutativity's anti-comm list (M2.3) but
        // string/list concat IS associative — anti-commutativity is
        // intentionally not applied as an associativity counter-signal.
        let summary = makeSummary(
            name: "concatenate",
            paramTypes: ("Array", "Array"),
            returnType: "Array"
        )
        let suggestion = try #require(AssociativityTemplate.suggest(for: summary))
        // Type-symmetry alone → 30, Possible.
        #expect(suggestion.score.total == 30)
        #expect(suggestion.score.tier == .possible)
    }

    // MARK: - Reducer/fold usage signal (PRD §5.3, +20)

    @Test("Reducer-fold usage adds 20 when the candidate's name is in the corpus reducerOps set")
    func reducerOpsSignalFiresWhenNamePresent() throws {
        let summary = makeSummary(
            name: "combine",
            paramTypes: ("State", "State"),
            returnType: "State"
        )
        // 30 type + 40 curated `combine` + 20 reducer = 90 → Strong.
        let suggestion = try #require(
            AssociativityTemplate.suggest(for: summary, reducerOps: ["combine"])
        )
        #expect(suggestion.score.total == 90)
        #expect(suggestion.score.tier == .strong)
        let reducerLine = suggestion.explainability.whySuggested.first { line in
            line.contains("Reduce/fold usage")
        }
        #expect(reducerLine == "Reduce/fold usage detected in corpus: 'combine' referenced as a reducer op (+20)")
    }

    @Test("Reducer-fold usage by itself doesn't fire when the candidate isn't referenced")
    func reducerOpsSignalAbsentWhenNameMissing() throws {
        let summary = makeSummary(
            name: "combine",
            paramTypes: ("State", "State"),
            returnType: "State"
        )
        let suggestion = try #require(
            AssociativityTemplate.suggest(for: summary, reducerOps: ["something_else"])
        )
        // 30 + 40 = 70, no reducer bonus.
        #expect(suggestion.score.total == 70)
    }

    @Test("Reducer-fold usage on an unnamed type-only candidate promotes Possible to Likely")
    func reducerOpsSignalAlonePromotesPossibleToLikely() throws {
        // No name match — domain-specific name not in the curated/vocab
        // list. Type alone (30) is .possible (20..<40); add reducer (20)
        // and the total reaches 50 → .likely (40..<75 per PRD §4.2).
        let summary = makeSummary(
            name: "fuse",
            paramTypes: ("Frame", "Frame"),
            returnType: "Frame"
        )
        let suggestion = try #require(
            AssociativityTemplate.suggest(for: summary, reducerOps: ["fuse"])
        )
        #expect(suggestion.score.total == 50)
        #expect(suggestion.score.tier == .likely)
    }

    // MARK: - Project vocabulary (commutativity verbs reused)

    @Test("Project-vocabulary commutativity verb on (T, T) -> T scores 70 (Likely)")
    func projectVocabularyVerb() {
        let summary = makeSummary(
            name: "unionGraphs",
            paramTypes: ("Graph", "Graph"),
            returnType: "Graph"
        )
        let vocabulary = Vocabulary(commutativityVerbs: ["unionGraphs"])
        let suggestion = AssociativityTemplate.suggest(for: summary, vocabulary: vocabulary)
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
        let suggestion = try #require(AssociativityTemplate.suggest(for: summary, vocabulary: vocabulary))
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
        let suggestion = AssociativityTemplate.suggest(for: summary, vocabulary: .empty)
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
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }

    // MARK: - Suggestion shape

    @Test("Suggestion carries the function as Evidence and uses 'associativity' template ID")
    func evidenceCarriesFunctionMetadata() throws {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set"
        )
        let suggestion = try #require(AssociativityTemplate.suggest(for: summary))
        #expect(suggestion.templateName == "associativity")
        let evidence = try #require(suggestion.evidence.first)
        #expect(evidence.displayName == "merge(_:_:)")
        #expect(evidence.signature == "(Set, Set) -> Set")
    }

    @Test("Generator and sampling are M2 placeholders (M3/M4 deferred)")
    func placeholderGeneratorAndSampling() throws {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set"
        )
        let suggestion = try #require(AssociativityTemplate.suggest(for: summary))
        #expect(suggestion.generator.source == .notYetComputed)
        #expect(suggestion.generator.confidence == nil)
        #expect(suggestion.generator.sampling == .notRun)
    }

    @Test("Equatable + class-equality + floating-point caveats populate the wrong-side block")
    func caveatsAlwaysPresent() throws {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set"
        )
        let suggestion = try #require(AssociativityTemplate.suggest(for: summary))
        #expect(suggestion.explainability.whyMightBeWrong.count == 3)
        #expect(suggestion.explainability.whyMightBeWrong[0].contains("Equatable"))
        #expect(suggestion.explainability.whyMightBeWrong[1].contains("class"))
        #expect(suggestion.explainability.whyMightBeWrong[2].contains("Floating-point"))
    }

    // MARK: - Suggestion identity

    @Test("Suggestion identity is namespaced by the 'associativity' template ID")
    func identityIncludesTemplateID() throws {
        let summary = makeSummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set"
        )
        let suggestion = try #require(AssociativityTemplate.suggest(for: summary))
        // Commutativity on the same signature would produce a different
        // identity because the template-ID prefix differs.
        let commutativityIdentity = SuggestionIdentity(
            canonicalInput: "commutativity|" + IdempotenceTemplate.canonicalSignature(of: summary)
        )
        #expect(suggestion.identity != commutativityIdentity)
    }

    // MARK: - Golden render

    @Test("Strong associativity suggestion (name + reducer) renders byte-for-byte against the M2 acceptance-bar golden")
    func strongAssociativityGoldenRender() throws {
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
        let suggestion = try #require(
            AssociativityTemplate.suggest(for: summary, reducerOps: ["merge"])
        )
        let rendered = SuggestionRenderer.render(suggestion)
        let expected = """
[Suggestion]
Template: associativity
Score:    90 (Strong)

Why suggested:
  ✓ merge(_:_:) (IntSet, IntSet) -> IntSet — Sources/Demo/Sets.swift:12
  ✓ Type-symmetry signature: (T, T) -> T (T = IntSet) (+30)
  ✓ Curated commutativity verb match: 'merge' (+40)
  ✓ Reduce/fold usage detected in corpus: 'merge' referenced as a reducer op (+20)

Why this might be wrong:
  ⚠ T must conform to Equatable for the emitted property to compile. \
SwiftInfer M1 does not verify protocol conformance — confirm before applying.
  ⚠ If T is a class with a custom ==, the property is over value equality as T.== defines it.
  ⚠ Floating-point operations are typically not exactly associative under IEEE 754 — \
a Double-typed candidate may pass the type pattern but fail sampling under M4.

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
