import Foundation
import Testing
import SwiftInferCore
@testable import SwiftInferCLI

@Suite("RefactorBridgeOrchestrator — per-type proposal aggregation (M7.5b)")
struct RefactorBridgeOrchestratorTests {

    // MARK: - Single-arm proposals

    @Test("Associativity-only on type T → Semigroup proposal")
    func associativityAloneFiresSemigroup() {
        let suggestion = makeSuggestion(template: "associativity", typeName: "Money")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [suggestion])
        let proposal = try? #require(proposals["Money"])
        #expect(proposal?.protocolName == "Semigroup")
        #expect(proposal?.relatedIdentities.contains(suggestion.identity) == true)
    }

    @Test("Associativity + identity-element on same T → Monoid proposal (Monoid wins)")
    func associativityPlusIdentityElementFiresMonoid() {
        let assoc = makeSuggestion(template: "associativity", typeName: "Tally", funcName: "merge")
        let identity = makeSuggestion(template: "identity-element", typeName: "Tally", funcName: "merge")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity])
        let proposal = try? #require(proposals["Tally"])
        #expect(proposal?.protocolName == "Monoid")
        #expect(proposal?.relatedIdentities.contains(assoc.identity) == true)
        #expect(proposal?.relatedIdentities.contains(identity.identity) == true)
    }

    // MARK: - Negative cases

    @Test("Identity-element alone (no associativity) → no proposal")
    func identityElementAloneSilent() {
        let suggestion = makeSuggestion(template: "identity-element", typeName: "Bag")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [suggestion])
        #expect(proposals["Bag"] == nil)
        #expect(proposals.isEmpty)
    }

    @Test("Commutativity alone → no proposal (M7.5 ships associativity-only Semigroup)")
    func commutativityAloneSilent() {
        let suggestion = makeSuggestion(template: "commutativity", typeName: "Money")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [suggestion])
        #expect(proposals["Money"] == nil)
    }

    @Test("Property-level templates produce no proposals")
    func propertyLevelTemplatesIgnored() {
        let suggestions = [
            makeSuggestion(template: "idempotence", typeName: "String"),
            makeSuggestion(template: "round-trip", typeName: "MyType"),
            makeSuggestion(template: "monotonicity", typeName: "Widget"),
            makeSuggestion(template: "invariant-preservation", typeName: "Widget")
        ]
        let proposals = RefactorBridgeOrchestrator.proposals(from: suggestions)
        #expect(proposals.isEmpty)
    }

    // MARK: - Per-type aggregation

    @Test("Multiple types each get their own proposal")
    func multipleTypesProduceMultipleProposals() {
        let moneyAssoc = makeSuggestion(template: "associativity", typeName: "Money", funcName: "add")
        let tallyAssoc = makeSuggestion(template: "associativity", typeName: "Tally", funcName: "combine")
        let tallyIdentity = makeSuggestion(template: "identity-element", typeName: "Tally", funcName: "combine")
        let proposals = RefactorBridgeOrchestrator.proposals(
            from: [moneyAssoc, tallyAssoc, tallyIdentity]
        )
        #expect(proposals.count == 2)
        #expect(proposals["Money"]?.protocolName == "Semigroup")
        #expect(proposals["Tally"]?.protocolName == "Monoid")
    }

    @Test("Two associativity suggestions on same type still produce one Semigroup proposal")
    func multipleAssociativityOnSameTypeAggregates() {
        // Two functions on `Money` both fire associativity: e.g. `add` and `mul`.
        let add = makeSuggestion(template: "associativity", typeName: "Money", funcName: "add")
        let mul = makeSuggestion(template: "associativity", typeName: "Money", funcName: "mul")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [add, mul])
        let proposal = try? #require(proposals["Money"])
        #expect(proposal?.protocolName == "Semigroup")
        #expect(proposal?.relatedIdentities.count == 2)
    }

    // MARK: - Explainability

    @Test("Proposal explainability cites every contributing suggestion")
    func explainabilityListsContributors() {
        let assoc = makeSuggestion(template: "associativity", typeName: "Tally", funcName: "merge")
        let identity = makeSuggestion(template: "identity-element", typeName: "Tally", funcName: "merge")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity])
        let why = proposals["Tally"]?.explainability.whySuggested ?? []
        #expect(why.contains { $0.contains("RefactorBridge claim") })
        #expect(why.contains { $0.contains("from associativity:") })
        #expect(why.contains { $0.contains("from identity-element:") })
    }

    // MARK: - Helpers

    private func makeSuggestion(
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
}
