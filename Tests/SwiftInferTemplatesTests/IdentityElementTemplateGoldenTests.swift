import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("IdentityElementTemplate — golden render")
struct IdentityElementTemplateGoldenTests {

    @Test("Strong identity-element suggestion (op + identity + empty-seed) renders byte-for-byte")
    func strongIdentityElementGoldenRender() throws {
        let pair = makeGoldenRenderPair()
        let suggestion = try #require(
            IdentityElementTemplate.suggest(for: pair, opsWithIdentitySeed: ["merge"])
        )
        let rendered = SuggestionRenderer.render(suggestion)
        #expect(rendered == expectedGoldenRender(suggestion: suggestion))
    }

    private func makeGoldenRenderPair() -> IdentityElementPair {
        let merge = FunctionSummary(
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
        let empty = IdentityCandidate(
            name: "empty",
            typeText: "IntSet",
            containingTypeName: "IntSet",
            location: SourceLocation(file: "Sources/Demo/Sets.swift", line: 5, column: 5)
        )
        return IdentityElementPair(operation: merge, identity: empty)
    }

    private func expectedGoldenRender(suggestion: Suggestion) -> String {
        let seedHex = SamplingSeed.renderHex(SamplingSeed.derive(from: suggestion.identity))
        return """
[Suggestion]
Template: identity-element
Score:    90 (Strong)

Why suggested:
  ✓ merge(_:_:) (IntSet, IntSet) -> IntSet — Sources/Demo/Sets.swift:12
  ✓ IntSet.empty: IntSet — Sources/Demo/Sets.swift:5
  ✓ Type-symmetry signature: (T, T) -> T with identity T.empty (T = IntSet) (+30)
  ✓ Curated identity-element constant: 'IntSet.empty' on type IntSet (+40)
  ✓ Accumulator-with-empty-seed: 'merge' used in .reduce(<identity-shape>, op) (+20)

Why this might be wrong:
  ⚠ T must conform to Equatable for the emitted property to compile. \
SwiftInfer M1 does not verify protocol conformance — confirm before applying.
  ⚠ If T is a class with a custom ==, the property is over value equality as T.== defines it.
  ⚠ The identity property is two-sided: f(t, e) == t AND f(e, t) == t. \
A one-sided identity (e.g. left-identity only) will pass the type pattern but \
fail one of the emitted assertions under M4 sampling.

Generator: not yet computed (M3 prerequisite)
Sampling:  not run; lifted test seed: \(seedHex)
Identity:  \(suggestion.identity.display)
Suppress:  // swiftinfer: skip \(suggestion.identity.display)
"""
    }
}
