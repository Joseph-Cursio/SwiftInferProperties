import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// MARK: - Shared helpers

func makeAssociativitySummary(
    name: String,
    returnType: String?,
    paramTypes: (String, String)? = nil,
    parameters explicitParameters: [Parameter]? = nil,
    isMutating: Bool = false,
    bodySignals: BodySignals = .empty
) -> FunctionSummary {
    let parameters: [Parameter]
    if let explicitParameters {
        parameters = explicitParameters
    } else if let paramTypes {
        parameters = [
            Parameter(label: nil, internalName: "lhs", typeText: paramTypes.0, isInout: false),
            Parameter(label: nil, internalName: "rhs", typeText: paramTypes.1, isInout: false),
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

func makeAssociativitySummary(
    name: String,
    parameters: [Parameter],
    returnType: String?
) -> FunctionSummary {
    makeAssociativitySummary(
        name: name,
        returnType: returnType,
        paramTypes: nil,
        parameters: parameters,
        isMutating: false,
        bodySignals: .empty
    )
}

@Suite("AssociativityTemplate — type pattern")
struct AssociativityTemplateTypePatternTests {

    @Test("B24 — a bare (T, T) -> T shape with no corroboration is suppressed, not Possible")
    func typeShapeAloneIsSuppressed() {
        // `blend` is not a curated/concat/operator name and isn't used as a
        // reducer, so the shape alone no longer surfaces associativity: a
        // correct non-monoid `(T,T)->T` (backoffDelay / weighted) matches the
        // shape without being associative. The shape signal still contributes
        // +30, but the B24 counter (-20) drops the net below the Possible floor.
        let summary = makeAssociativitySummary(
            name: "blend",
            returnType: "Color",
            paramTypes: ("Color", "Color")
        )
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
        let signals = AssociativityTemplate.accumulatedSignals(
            for: summary,
            vocabulary: .empty,
            reducerOps: [],
            inheritedTypesByName: [:]
        )
        #expect(signals.contains { $0.kind == .typeSymmetrySignature && $0.weight == 30 })
        #expect(signals.contains { $0.kind == .unsupportedAlgebraicShape && $0.weight == -20 })
    }

    @Test("Curated commutativity verb on (T, T) -> T scores 70 (Likely) under associativity too")
    func curatedVerbAdds40() {
        // Per v0.2 §5.2 "Name signals: same as commutativity. Often
        // suggested alongside." — associativity reuses the commutativity
        // curated list with no dedicated `associativityVerbs` vocab key.
        let summary = makeAssociativitySummary(
            name: "merge",
            returnType: "Set",
            paramTypes: ("Set", "Set")
        )
        let suggestion = AssociativityTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 70)
        #expect(suggestion?.score.tier == .likely)
    }

    @Test("Single-parameter function never matches the associativity pattern")
    func singleParamDoesNotMatch() {
        let summary = makeAssociativitySummary(
            name: "merge",
            parameters: [Parameter(label: nil, internalName: "x", typeText: "Set", isInout: false)],
            returnType: "Set"
        )
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Three-parameter function never matches the associativity pattern")
    func threeParamDoesNotMatch() {
        let summary = makeAssociativitySummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "Set", isInout: false),
                Parameter(label: nil, internalName: "b", typeText: "Set", isInout: false),
                Parameter(label: nil, internalName: "c", typeText: "Set", isInout: false),
            ],
            returnType: "Set"
        )
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Mismatched parameter types do not match")
    func mismatchedParamTypesDoNotMatch() {
        let summary = makeAssociativitySummary(
            name: "merge",
            returnType: "Set",
            paramTypes: ("Set", "Array")
        )
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Return type that doesn't match params does not match")
    func mismatchedReturnTypeDoesNotMatch() {
        let summary = makeAssociativitySummary(
            name: "merge",
            returnType: "Bool",
            paramTypes: ("Set", "Set")
        )
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }

    @Test("inout on either parameter disqualifies")
    func inoutDisqualifies() {
        let summary = makeAssociativitySummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "Set", isInout: true),
                Parameter(label: nil, internalName: "b", typeText: "Set", isInout: false),
            ],
            returnType: "Set"
        )
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }

    @Test("mutating disqualifies")
    func mutatingDisqualifies() {
        let summary = makeAssociativitySummary(
            name: "merge",
            returnType: "Set",
            paramTypes: ("Set", "Set"),
            isMutating: true
        )
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Void return is rejected")
    func voidReturnRejected() {
        let summary = makeAssociativitySummary(
            name: "merge",
            returnType: "Void",
            paramTypes: ("Void", "Void")
        )
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Anti-commutativity verb does NOT suppress associativity (concat is associative)")
    func antiCommutativityDoesNotSuppressAssociativity() throws {
        // `concatenate` IS in commutativity's anti-comm list (M2.3) but
        // string/list concat IS associative — anti-commutativity is
        // intentionally not applied as an associativity counter-signal.
        let summary = makeAssociativitySummary(
            name: "concatenate",
            returnType: "Array",
            paramTypes: ("Array", "Array")
        )
        let suggestion = try #require(AssociativityTemplate.suggest(for: summary))
        // Type-symmetry alone → 30, Possible.
        #expect(suggestion.score.total == 30)
        #expect(suggestion.score.tier == .possible)
    }
}
