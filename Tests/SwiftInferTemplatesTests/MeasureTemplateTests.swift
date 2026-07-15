import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The measure role and its one free law — non-negativity, `measure >= 0`. Fires
/// on a curated cardinality/magnitude name returning a SIGNED integer, in three
/// shapes (0-param property, 0-param method, 1-param function). Deliberately
/// Possible-tier: it is the weakest law in the catalogue, true almost always,
/// earning its keep only on the integer-underflow edge — so it stays below the
/// additive `homomorphism` on the same measure and is surfaced only with
/// `--include-possible`.
@Suite("Measure — non-negativity of a cardinality / magnitude")
struct MeasureTemplateTests {

    private static let loc = SourceLocation(file: "Measures.swift", line: 1, column: 1)

    /// A 0-parameter measure of `self` — a computed property or nullary method.
    private func selfMeasure(
        _ name: String,
        returns: String?,
        on type: String? = "Bag",
        computedProperty: Bool = false,
        mutating: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [],
            returnTypeText: returns,
            isThrows: false,
            isAsync: false,
            isMutating: mutating,
            isStatic: false,
            location: Self.loc,
            containingTypeName: type,
            bodySignals: .empty,
            isComputedProperty: computedProperty
        )
    }

    /// A 1-parameter measure of its argument.
    private func argMeasure(_ name: String, param: String, returns: String?) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "value", typeText: param, isInout: false)],
            returnTypeText: returns,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: true,
            location: Self.loc,
            containingTypeName: "FreeOps",
            bodySignals: .empty
        )
    }

    @Test("a computed-property count owes measure >= 0, at Possible")
    func computedPropertyCountFires() throws {
        let count = selfMeasure("count", returns: "Int", computedProperty: true)
        #expect(MeasureTemplate.isMeasure(count))

        let suggestion = try #require(MeasureTemplate.suggest(for: count))
        #expect(suggestion.templateName == "measure-non-negativity")
        #expect(suggestion.score.total == 35)
        #expect(suggestion.score.tier == .possible)
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("measure >= 0"))
        #expect(caveats.contains("integer underflow"))
    }

    @Test("a nullary size method fires")
    func nullaryMethodFires() {
        #expect(MeasureTemplate.isMeasure(selfMeasure("size", returns: "Int")))
    }

    @Test("a 1-parameter measure of its argument fires")
    func oneParamMeasureFires() {
        #expect(MeasureTemplate.isMeasure(argMeasure("length", param: "String", returns: "Int")))
    }

    @Test("a suffixed measure name (byteCount) fires")
    func suffixedMeasureFires() {
        #expect(MeasureTemplate.isMeasure(selfMeasure("byteCount", returns: "Int", computedProperty: true)))
    }

    @Test("a UInt codomain does NOT fire — the type already guarantees >= 0")
    func unsignedCodomainRejected() {
        let count = selfMeasure("count", returns: "UInt", computedProperty: true)
        #expect(MeasureTemplate.isMeasure(count) == false)
        #expect(MeasureTemplate.suggest(for: count) == nil)
    }

    @Test("a signed measure name (balance) is deliberately excluded")
    func signedMeasureNameRejected() {
        // A balance / delta can be negative, so non-negativity would be a false law.
        let balance = selfMeasure("balance", returns: "Int", computedProperty: true)
        #expect(MeasureTemplate.isMeasure(balance) == false)
    }

    @Test("a non-measure name does NOT fire")
    func nonMeasureNameRejected() {
        #expect(MeasureTemplate.isMeasure(selfMeasure("label", returns: "Int", computedProperty: true)) == false)
    }

    @Test("a mutating measure does NOT fire — not the pure self -> Int map")
    func mutatingMeasureRejected() {
        #expect(MeasureTemplate.isMeasure(selfMeasure("size", returns: "Int", mutating: true)) == false)
    }

    @Test("a 0-param measure with no containing type does NOT fire — nothing to generate")
    func topLevelNullaryMeasureRejected() {
        #expect(MeasureTemplate.isMeasure(selfMeasure("count", returns: "Int", on: nil)) == false)
    }

    @Test("a 2-parameter function of the right name does NOT fire — not a lone measure")
    func twoParamRejected() {
        let two = FunctionSummary(
            name: "count",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "Int", isInout: false),
                Parameter(label: nil, internalName: "b", typeText: "Int", isInout: false)
            ],
            returnTypeText: "Int",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: true,
            location: Self.loc,
            containingTypeName: "FreeOps",
            bodySignals: .empty
        )
        #expect(MeasureTemplate.isMeasure(two) == false)
    }
}
