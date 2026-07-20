import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The equivalence-relation template — a named equality (`isEqual(to:)` /
/// `areEqual(_:_:)`) over two same-type operands, owing reflexivity + symmetry +
/// transitivity, the `==` analog of the comparator's strict weak ordering.
@Suite("EquivalenceRelationTemplate — named equality laws")
struct EquivalenceRelationTemplateTests {

    private static let loc = SourceLocation(file: "Money.swift", line: 1, column: 1)

    private func member(
        _ name: String,
        _ parameters: [Parameter],
        returns: String? = "Bool",
        type: String? = "Money",
        isStatic: Bool = false,
        isAsync: Bool = false,
        isThrows: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returns,
            isThrows: isThrows,
            isAsync: isAsync,
            isMutating: false,
            isStatic: isStatic,
            location: Self.loc,
            containingTypeName: type,
            bodySignals: .empty
        )
    }

    private func parameter(_ label: String?, _ type: String) -> Parameter {
        Parameter(label: label, internalName: "value", typeText: type, isInout: false)
    }

    @Test("an instance isEqual(to: Self) is an equivalence at Likely 40 with the three laws")
    func instanceEqualityFires() throws {
        let isEqual = member("isEqual", [parameter("to", "Money")])
        #expect(EquivalenceRelationTemplate.isEquivalenceRelation(isEqual))

        let suggestion = try #require(EquivalenceRelationTemplate.suggest(for: isEqual))
        #expect(suggestion.templateName == "equivalence-relation")
        #expect(suggestion.score.total == 40)
        #expect(suggestion.score.tier == .likely)

        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("REFLEXIVITY, SYMMETRY, TRANSITIVITY"))
        #expect(caveats.contains("TRANSITIVITY is the clause"))
        #expect(caveats.contains("CONSISTENT with `hashValue`"))
    }

    @Test("`Self`-typed argument is accepted for the instance form")
    func selfTypedArgumentAccepted() {
        let equals = member("equals", [parameter("to", "Self")])
        #expect(EquivalenceRelationTemplate.isEquivalenceRelation(equals))
    }

    @Test("a binary areEqual(_:_:) is an equivalence, NOT a comparator")
    func binaryEqualityFires() throws {
        let areEqual = member(
            "areEqual",
            [parameter(nil, "Money"), parameter(nil, "Money")],
            isStatic: true
        )
        #expect(EquivalenceRelationTemplate.isEquivalenceRelation(areEqual))
        // Equivalence wins the shape over comparator (both are positional (T,T)->Bool).
        let suggestion = try #require(EquivalenceRelationTemplate.suggest(for: areEqual))
        #expect(suggestion.templateName == "equivalence-relation")
    }

    // MARK: - The boundaries

    @Test("a CROSS-type isEqualSet(to: Range) is NOT an equivalence (operands cannot swap)")
    func crossTypeIsNotEquivalence() {
        // The swift-syntax `isEqualSet(to: Range<Int>)` boundary: a BitSet-vs-Range
        // comparison has no symmetry, so no equivalence law applies.
        let isEqualSet = member("isEqualSet", [parameter("to", "Range<Int>")], type: "BitSet")
        #expect(EquivalenceRelationTemplate.isEquivalenceRelation(isEqualSet) == false)
        #expect(EquivalenceRelationTemplate.suggest(for: isEqualSet) == nil)
    }

    @Test("a non-equality name is NOT an equivalence (the name gate)")
    func nonEqualityNameRejected() {
        // `precedes` is a comparator, `isChild` a predicate — neither claims equality.
        let precedes = member("precedes", [parameter(nil, "Money"), parameter(nil, "Money")])
        let isChild = member("isChild", [parameter(nil, "Money"), parameter("of", "Money")])
        #expect(EquivalenceRelationTemplate.isEquivalenceRelation(precedes) == false)
        #expect(EquivalenceRelationTemplate.isEquivalenceRelation(isChild) == false)
    }

    @Test("the == operator is excluded — Equatable's law, run by the kit")
    func operatorExcluded() {
        let equals = member("==", [parameter(nil, "Money"), parameter(nil, "Money")], isStatic: true)
        #expect(EquivalenceRelationTemplate.isEquivalenceRelation(equals) == false)
    }

    @Test("async / throwing equality is not verifiable as a pure relation")
    func asyncThrowsRejected() {
        let asyncEqual = member("isEqual", [parameter("to", "Money")], isAsync: true)
        let throwingEqual = member("isEqual", [parameter("to", "Money")], isThrows: true)
        #expect(EquivalenceRelationTemplate.isEquivalenceRelation(asyncEqual) == false)
        #expect(EquivalenceRelationTemplate.isEquivalenceRelation(throwingEqual) == false)
    }

    @Test("a non-Bool return is not an equality")
    func nonBoolRejected() {
        let notBool = member("isEqual", [parameter("to", "Money")], returns: "Int")
        #expect(EquivalenceRelationTemplate.isEquivalenceRelation(notBool) == false)
    }
}
