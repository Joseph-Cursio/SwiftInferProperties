import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("AssociativityTemplate — suggestion shape, identity, golden render")
struct AssociativityTemplateGoldenTests {

    @Test("Suggestion carries the function as Evidence and uses 'associativity' template ID")
    func evidenceCarriesFunctionMetadata() throws {
        let summary = makeAssociativitySummary(
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
        let summary = makeAssociativitySummary(
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
        let summary = makeAssociativitySummary(
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

    @Test("Suggestion identity is namespaced by the 'associativity' template ID")
    func identityIncludesTemplateID() throws {
        let summary = makeAssociativitySummary(
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
        let seedHex = SamplingSeed.renderHex(SamplingSeed.derive(from: suggestion.identity))
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
Sampling:  not run; lifted test seed: \(seedHex)
Identity:  \(suggestion.identity.display)
Suppress:  // swiftinfer: skip \(suggestion.identity.display)
"""
        #expect(rendered == expected)
    }
}
