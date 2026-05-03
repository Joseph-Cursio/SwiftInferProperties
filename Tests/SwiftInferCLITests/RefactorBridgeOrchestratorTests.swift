import Foundation
import Testing
import SwiftInferCore
import SwiftInferTemplates
@testable import SwiftInferCLI

@Suite("RefactorBridgeOrchestrator — single-arm + per-type aggregation (M7.5b)")
struct RefactorBridgeOrchestratorTests {

    // MARK: - Single-arm proposals

    @Test("Associativity-only on type T → Semigroup proposal")
    func associativityAloneFiresSemigroup() {
        let suggestion = makeRBSuggestion(template: "associativity", typeName: "Money")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [suggestion])
        let proposal = proposals["Money"]?.first
        #expect(proposal?.protocolName == "Semigroup")
        #expect(proposal?.relatedIdentities.contains(suggestion.identity) == true)
    }

    @Test("Associativity + identity-element on same T → Monoid proposal (Monoid wins)")
    func associativityPlusIdentityElementFiresMonoid() {
        let assoc = makeRBSuggestion(template: "associativity", typeName: "Tally", funcName: "merge")
        let identity = makeRBSuggestion(template: "identity-element", typeName: "Tally", funcName: "merge")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity])
        let proposal = proposals["Tally"]?.first
        #expect(proposal?.protocolName == "Monoid")
        #expect(proposal?.relatedIdentities.contains(assoc.identity) == true)
        #expect(proposal?.relatedIdentities.contains(identity.identity) == true)
    }

    // MARK: - Negative cases

    @Test("Identity-element alone (no associativity) → no proposal")
    func identityElementAloneSilent() {
        let suggestion = makeRBSuggestion(template: "identity-element", typeName: "Bag")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [suggestion])
        #expect(proposals["Bag"] == nil)
        #expect(proposals.isEmpty)
    }

    @Test("Commutativity alone → no proposal (M7.5 ships associativity-only Semigroup)")
    func commutativityAloneSilent() {
        let suggestion = makeRBSuggestion(template: "commutativity", typeName: "Money")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [suggestion])
        #expect(proposals["Money"] == nil)
    }

    @Test("Property-level templates produce no proposals")
    func propertyLevelTemplatesIgnored() {
        let suggestions = [
            makeRBSuggestion(template: "idempotence", typeName: "String"),
            makeRBSuggestion(template: "round-trip", typeName: "MyType"),
            makeRBSuggestion(template: "monotonicity", typeName: "Widget"),
            makeRBSuggestion(template: "invariant-preservation", typeName: "Widget")
        ]
        let proposals = RefactorBridgeOrchestrator.proposals(from: suggestions)
        #expect(proposals.isEmpty)
    }

    // MARK: - Per-type aggregation

    @Test("Multiple types each get their own proposal")
    func multipleTypesProduceMultipleProposals() {
        let moneyAssoc = makeRBSuggestion(template: "associativity", typeName: "Money", funcName: "add")
        let tallyAssoc = makeRBSuggestion(template: "associativity", typeName: "Tally", funcName: "combine")
        let tallyIdentity = makeRBSuggestion(template: "identity-element", typeName: "Tally", funcName: "combine")
        let proposals = RefactorBridgeOrchestrator.proposals(
            from: [moneyAssoc, tallyAssoc, tallyIdentity]
        )
        #expect(proposals.count == 2)
        #expect(proposals["Money"]?.first?.protocolName == "Semigroup")
        #expect(proposals["Tally"]?.first?.protocolName == "Monoid")
    }

    @Test("Two associativity suggestions on same type still produce one Semigroup proposal")
    func multipleAssociativityOnSameTypeAggregates() {
        // Two functions on `Money` both fire associativity: e.g. `add` and `mul`.
        let add = makeRBSuggestion(template: "associativity", typeName: "Money", funcName: "add")
        let mul = makeRBSuggestion(template: "associativity", typeName: "Money", funcName: "mul")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [add, mul])
        let proposal = proposals["Money"]?.first
        #expect(proposal?.protocolName == "Semigroup")
        #expect(proposal?.relatedIdentities.count == 2)
    }

    // MARK: - Explainability

    @Test("Proposal explainability cites every contributing suggestion")
    func explainabilityListsContributors() {
        let assoc = makeRBSuggestion(template: "associativity", typeName: "Tally", funcName: "merge")
        let identity = makeRBSuggestion(template: "identity-element", typeName: "Tally", funcName: "merge")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity])
        let why = proposals["Tally"]?.first?.explainability.whySuggested ?? []
        #expect(why.contains { $0.contains("RefactorBridge claim") })
        #expect(why.contains { $0.contains("from associativity:") })
        #expect(why.contains { $0.contains("from identity-element:") })
    }

    // MARK: - Witness extraction (M7.5.a)

    @Test("Semigroup proposal carries the binary op's bare name as combineWitness")
    func semigroupCarriesCombineWitness() {
        let assoc = makeRBSuggestion(template: "associativity", typeName: "Money", funcName: "merge")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc])
        let proposal = proposals["Money"]?.first
        #expect(proposal?.combineWitness == "merge")
        #expect(proposal?.identityWitness == nil)
    }

    @Test("Monoid proposal carries both binary op and identity element witnesses")
    func monoidCarriesBothWitnesses() {
        let assoc = makeRBSuggestion(template: "associativity", typeName: "Tally", funcName: "merge")
        let identity = makeRBIdentityElementSuggestion(
            typeName: "Tally",
            opName: "merge",
            identityName: "empty"
        )
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity])
        let proposal = proposals["Tally"]?.first
        #expect(proposal?.combineWitness == "merge")
        #expect(proposal?.identityWitness == "empty")
    }

    @Test("Identity witness strips the qualifying type prefix")
    func identityWitnessStripsTypePrefix() {
        let assoc = makeRBSuggestion(template: "associativity", typeName: "Tally", funcName: "merge")
        // IdentityElementTemplate emits a qualified displayName like
        // `"Tally.empty"`; the orchestrator strips the type prefix.
        let identity = makeRBIdentityElementSuggestion(
            typeName: "Tally",
            opName: "merge",
            identityDisplayName: "Tally.empty"
        )
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity])
        #expect(proposals["Tally"]?.first?.identityWitness == "empty")
    }

    @Test("Witness names propagate when only the identity-element suggestion contributes the binary op evidence")
    func witnessNamesFromIdentityElementAlone() {
        // Edge case: Semigroup gate is associativity-only. An identity-
        // element alone shouldn't produce any proposal.
        let identity = makeRBIdentityElementSuggestion(
            typeName: "Tally",
            opName: "merge",
            identityName: "empty"
        )
        let proposals = RefactorBridgeOrchestrator.proposals(from: [identity])
        #expect(proposals["Tally"] == nil)
    }
}

// MARK: - Shared fixture helpers

func makeRBSuggestion(
    template: String,
    typeName: String,
    funcName: String = "operation"
) -> Suggestion {
    let signature = "(\(typeName), \(typeName)) -> \(typeName)"
    let evidence = Evidence(
        displayName: "\(funcName)(_:_:)",
        signature: signature,
        location: SourceLocation(file: "Test.swift", line: 1, column: 1)
    )
    let identityHash = "\(template)|\(funcName)|\(typeName)"
    return Suggestion(
        templateName: template,
        evidence: [evidence],
        score: Score(signals: []),
        generator: .m1Placeholder,
        explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
        identity: SuggestionIdentity(canonicalInput: identityHash)
    )
}

/// Build an identity-element suggestion with the two-row evidence
/// shape `IdentityElementTemplate.suggest` produces. The orchestrator
/// reads evidence[0] for combineWitness, evidence[1] for
/// identityWitness.
func makeRBIdentityElementSuggestion(
    typeName: String,
    opName: String,
    identityName: String? = nil,
    identityDisplayName: String? = nil
) -> Suggestion {
    let opEvidence = Evidence(
        displayName: "\(opName)(_:_:)",
        signature: "(\(typeName), \(typeName)) -> \(typeName)",
        location: SourceLocation(file: "Test.swift", line: 1, column: 1)
    )
    let displayName = identityDisplayName ?? identityName ?? "empty"
    let identityEvidence = Evidence(
        displayName: displayName,
        signature: ": \(typeName)",
        location: SourceLocation(file: "Test.swift", line: 5, column: 1)
    )
    return Suggestion(
        templateName: "identity-element",
        evidence: [opEvidence, identityEvidence],
        score: Score(signals: []),
        generator: .m1Placeholder,
        explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
        identity: SuggestionIdentity(canonicalInput: "identity-element|\(opName)|\(typeName)")
    )
}

func makeRBInversePair(
    typeName: String,
    opName: String,
    inverseName: String
) -> InverseElementPair {
    let operation = FunctionSummary(
        name: opName,
        parameters: [
            Parameter(label: nil, internalName: "lhs", typeText: typeName, isInout: false),
            Parameter(label: nil, internalName: "rhs", typeText: typeName, isInout: false)
        ],
        returnTypeText: typeName,
        isThrows: false,
        isAsync: false,
        isMutating: false,
        isStatic: false,
        location: SourceLocation(file: "Test.swift", line: 1, column: 1),
        containingTypeName: nil,
        bodySignals: .empty
    )
    let inverse = FunctionSummary(
        name: inverseName,
        parameters: [
            Parameter(label: nil, internalName: "value", typeText: typeName, isInout: false)
        ],
        returnTypeText: typeName,
        isThrows: false,
        isAsync: false,
        isMutating: false,
        isStatic: false,
        location: SourceLocation(file: "Test.swift", line: 5, column: 1),
        containingTypeName: nil,
        bodySignals: .empty
    )
    return InverseElementPair(operation: operation, inverse: inverse)
}
