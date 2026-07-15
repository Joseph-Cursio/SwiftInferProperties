import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The additive-measure homomorphism — `h(a + b) == h(a) + h(b)`. Deliberately
/// narrow: it fires only where the law is genuinely entailed (an integer measure
/// over an array `[T]`, whose `+` is free concatenation), and stays silent on the
/// containers where the measure is sub-additive (Set) or not additive at all
/// (String grapheme count).
@Suite("Homomorphism — additive measure over concatenation")
struct HomomorphismTemplateTests {

    private static let loc = SourceLocation(file: "Measures.swift", line: 1, column: 1)

    private func measure(_ name: String, param: String, returns: String?) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "items", typeText: param, isInout: false)],
            returnTypeText: returns,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: Self.loc,
            containingTypeName: nil,
            bodySignals: .empty
        )
    }

    @Test("an integer measure over an array owes h(a + b) == h(a) + h(b)")
    func measureOverArrayFires() throws {
        let count = measure("count", param: "[Int]", returns: "Int")
        #expect(HomomorphismTemplate.isAdditiveMeasure(count))

        let suggestion = try #require(HomomorphismTemplate.suggest(for: count))
        #expect(suggestion.templateName == "homomorphism")
        #expect(suggestion.score.total == 70)
        #expect(suggestion.score.tier == .likely)
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("h(a + b) == h(a) + h(b)"))
    }

    @Test("a suffixed measure name (byteCount) fires")
    func suffixedMeasureFires() {
        let byteCount = measure("byteCount", param: "[UInt8]", returns: "Int")
        #expect(HomomorphismTemplate.isAdditiveMeasure(byteCount))
    }

    @Test("Set is sub-additive — a measure over a Set does NOT fire")
    func setDomainRejected() {
        // |A ∪ B| <= |A| + |B|, so `size(a ∪ b) == size(a) + size(b)` is false.
        let size = measure("size", param: "Set<Int>", returns: "Int")
        #expect(HomomorphismTemplate.isAdditiveMeasure(size) == false)
        #expect(HomomorphismTemplate.suggest(for: size) == nil)
    }

    @Test("String grapheme count is not additive across a boundary — does NOT fire")
    func stringDomainRejected() {
        let length = measure("length", param: "String", returns: "Int")
        #expect(HomomorphismTemplate.isAdditiveMeasure(length) == false)
        #expect(HomomorphismTemplate.suggest(for: length) == nil)
    }

    @Test("an array function that is not a measure (max) does NOT fire")
    func nonMeasureNameRejected() {
        // `max(a + b) != max(a) + max(b)` — max is not additive.
        let maximum = measure("maximum", param: "[Int]", returns: "Int")
        #expect(HomomorphismTemplate.isAdditiveMeasure(maximum) == false)
    }

    @Test("a Double codomain is excluded — floating-point + is not associative")
    func floatingPointCodomainRejected() {
        let sum = measure("sum", param: "[Double]", returns: "Double")
        #expect(HomomorphismTemplate.isAdditiveMeasure(sum) == false)
    }
}
