import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("AssociativityTemplate — type pattern")
struct AssociativityTemplateTypePatternTests {

    @Test("Two same-type params and matching return scores 30 (Possible) with no name signal")
    func typeShapeAlone() {
        let summary = makeAssociativitySummary(
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
        let summary = makeAssociativitySummary(
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
                Parameter(label: nil, internalName: "c", typeText: "Set", isInout: false)
            ],
            returnType: "Set"
        )
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Mismatched parameter types do not match")
    func mismatchedParamTypesDoNotMatch() {
        let summary = makeAssociativitySummary(
            name: "merge",
            paramTypes: ("Set", "Array"),
            returnType: "Set"
        )
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Return type that doesn't match params does not match")
    func mismatchedReturnTypeDoesNotMatch() {
        let summary = makeAssociativitySummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Bool"
        )
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }

    @Test("inout on either parameter disqualifies")
    func inoutDisqualifies() {
        let summary = makeAssociativitySummary(
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
        let summary = makeAssociativitySummary(
            name: "merge",
            paramTypes: ("Set", "Set"),
            returnType: "Set",
            isMutating: true
        )
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }

    @Test("Void return is rejected")
    func voidReturnRejected() {
        let summary = makeAssociativitySummary(
            name: "merge",
            paramTypes: ("Void", "Void"),
            returnType: "Void"
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
            paramTypes: ("Array", "Array"),
            returnType: "Array"
        )
        let suggestion = try #require(AssociativityTemplate.suggest(for: summary))
        // Type-symmetry alone → 30, Possible.
        #expect(suggestion.score.total == 30)
        #expect(suggestion.score.tier == .possible)
    }
}

@Suite("AssociativityTemplate — reducer/fold + vocabulary + vetoes")
struct AssociativityTemplateBehaviorTests {

    // MARK: - Reducer/fold usage signal (PRD §5.3, +20)

    @Test("Reducer-fold usage adds 20 when the candidate's name is in the corpus reducerOps set")
    func reducerOpsSignalFiresWhenNamePresent() throws {
        let summary = makeAssociativitySummary(
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
        let summary = makeAssociativitySummary(
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
        let summary = makeAssociativitySummary(
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
        let summary = makeAssociativitySummary(
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
        let summary = makeAssociativitySummary(
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
        let summary = makeAssociativitySummary(
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
        let summary = makeAssociativitySummary(
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
}

// MARK: - Shared helpers

func makeAssociativitySummary(
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

func makeAssociativitySummary(
    name: String,
    parameters: [Parameter],
    returnType: String?
) -> FunctionSummary {
    makeAssociativitySummary(
        name: name,
        paramTypes: nil,
        parameters: parameters,
        returnType: returnType,
        isMutating: false,
        bodySignals: .empty
    )
}
