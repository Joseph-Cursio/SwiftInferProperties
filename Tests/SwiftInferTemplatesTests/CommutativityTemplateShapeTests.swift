import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// Split out of CommutativityTemplateTests.swift (file_length cap). Shares the
// `makeCommutativitySummary` builders in CommutativityTestSupport.swift.
@Suite("CommutativityTemplate — suggestion shape, identity, golden render")
struct CommutativityTemplateShapeTests {

    @Test("Suggestion carries the function as Evidence and uses 'commutativity' template ID")
    func evidenceCarriesFunctionMetadata() throws {
        let summary = makeCommutativitySummary(
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
        let summary = makeCommutativitySummary(
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
        let summary = makeCommutativitySummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set"
        )
        let suggestion = try #require(CommutativityTemplate.suggest(for: summary))
        #expect(suggestion.explainability.whyMightBeWrong.count == 2)
        #expect(suggestion.explainability.whyMightBeWrong[0].contains("Equatable"))
        #expect(suggestion.explainability.whyMightBeWrong[1].contains("class"))
    }

    @Test("Suggestion identity is namespaced by the 'commutativity' template ID")
    func identityIncludesTemplateID() throws {
        let summary = makeCommutativitySummary(
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
        let seedHex = SamplingSeed.renderHex(SamplingSeed.derive(from: suggestion.identity))
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
Sampling:  not run; lifted test seed: \(seedHex)
Identity:  \(suggestion.identity.display)
Suppress:  // swiftinfer: skip \(suggestion.identity.display)
"""
        #expect(rendered == expected)
    }
}
