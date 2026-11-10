import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

@Suite("RefactorBridgeOrchestrator — M8.4.b.2 Ring detection")
struct RefactorBridgeOrchestratorRingTests {

    @Test("Two Monoid-shaped ops (additive + multiplicative) → Ring proposal")
    func ringFiresOnAdditivePlusMultiplicative() throws {
        // `Money` has two Monoid-shaped ops: `add` (additive name) and
        // `multiply` (multiplicative name). PRD §5.4 row 5 → stdlib
        // `Numeric` writeout.
        let addAssoc = makeRBSuggestion(template: "associativity", typeName: "Money", funcName: "add")
        let addIdentity = makeRBIdentityElementSuggestion(
            typeName: "Money",
            opName: "add",
            identityName: "zero",
            identityDisplayName: "Money.zero"
        )
        let mulAssoc = makeRBSuggestion(template: "associativity", typeName: "Money", funcName: "multiply")
        let mulIdentity = makeRBIdentityElementSuggestion(
            typeName: "Money",
            opName: "multiply",
            identityName: "one",
            identityDisplayName: "Money.one"
        )
        let proposals = RefactorBridgeOrchestrator.proposals(
            from: [addAssoc, addIdentity, mulAssoc, mulIdentity]
        )
        let list = try #require(proposals["Money"])
        #expect(list.count == 1)
        #expect(list[0].protocolName == "Numeric")
        // combineWitness carries the additive op name for display;
        // identityWitness carries the additive identity (zero).
        #expect(list[0].combineWitness == "add")
        #expect(list[0].identityWitness == "zero")
    }

    @Test("Ring explainability lists both ops + Numeric requirement caveats")
    func ringExplainabilityCovers() throws {
        let addAssoc = makeRBSuggestion(template: "associativity", typeName: "Money", funcName: "plus")
        let addIdentity = makeRBIdentityElementSuggestion(
            typeName: "Money",
            opName: "plus",
            identityName: "zero"
        )
        let mulAssoc = makeRBSuggestion(template: "associativity", typeName: "Money", funcName: "times")
        let mulIdentity = makeRBIdentityElementSuggestion(
            typeName: "Money",
            opName: "times",
            identityName: "one"
        )
        let proposals = RefactorBridgeOrchestrator.proposals(
            from: [addAssoc, addIdentity, mulAssoc, mulIdentity]
        )
        let proposal = try #require(proposals["Money"]?.first)
        let why = proposal.explainability.whySuggested.joined(separator: "\n")
        #expect(why.contains("RefactorBridge claim: Money → Ring"))
        #expect(why.contains("additive op: plus(_:_:) with identity zero"))
        #expect(why.contains("multiplicative op: times(_:_:) with identity one"))
        let caveats = proposal.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("Distributivity"))
        #expect(caveats.contains("NOT sample-verified"))
        #expect(caveats.contains("FloatingPoint caveat"))
    }

    @Test("Single op with both additive AND multiplicative names doesn't fire Ring")
    func ringRequiresTwoDistinctOps() throws {
        // Edge case: the curated lists don't include `combine`, so this
        // won't fire — the test pins the "two distinct ops" intent.
        let assoc = makeRBSuggestion(template: "associativity", typeName: "T", funcName: "add")
        let identity = makeRBIdentityElementSuggestion(typeName: "T", opName: "add", identityName: "zero")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity])
        let proposal = try #require(proposals["T"]?.first)
        // Only one op with Monoid shape → falls back to Monoid.
        #expect(proposal.protocolName == "Monoid")
    }

    @Test("Two ops on the same type with non-curated names do NOT fire Ring")
    func ringRequiresCuratedNaming() throws {
        // `merge` and `combine` are both Monoid-shaped but neither is
        // in the curated additive / multiplicative lists.
        let mergeAssoc = makeRBSuggestion(template: "associativity", typeName: "T", funcName: "merge")
        let mergeIdentity = makeRBIdentityElementSuggestion(
            typeName: "T",
            opName: "merge",
            identityName: "empty"
        )
        let combineAssoc = makeRBSuggestion(template: "associativity", typeName: "T", funcName: "combine")
        let combineIdentity = makeRBIdentityElementSuggestion(
            typeName: "T",
            opName: "combine",
            identityName: "empty"
        )
        let proposals = RefactorBridgeOrchestrator.proposals(
            from: [mergeAssoc, mergeIdentity, combineAssoc, combineIdentity]
        )
        let proposal = try #require(proposals["T"]?.first)
        #expect(proposal.protocolName == "Monoid")
        #expect(proposals["T"]?.contains { $0.protocolName == "Numeric" } == false)
    }

    @Test("Ring requires BOTH ops to be Monoid-shaped (assoc + identity)")
    func ringRequiresMonoidShapeOnBothOps() throws {
        // `add` has assoc + identity; `multiply` has assoc only (no
        // identity). Ring shouldn't fire — falls back to Monoid.
        let addAssoc = makeRBSuggestion(template: "associativity", typeName: "T", funcName: "add")
        let addIdentity = makeRBIdentityElementSuggestion(typeName: "T", opName: "add", identityName: "zero")
        let mulAssoc = makeRBSuggestion(template: "associativity", typeName: "T", funcName: "multiply")
        let proposals = RefactorBridgeOrchestrator.proposals(
            from: [addAssoc, addIdentity, mulAssoc]
        )
        let proposal = try #require(proposals["T"]?.first)
        #expect(proposal.protocolName == "Monoid")
    }

    @Test("Ring's relatedIdentities covers all contributing suggestions")
    func ringRelatedIdentitiesCoverAll() throws {
        let addAssoc = makeRBSuggestion(template: "associativity", typeName: "Money", funcName: "add")
        let addIdentity = makeRBIdentityElementSuggestion(typeName: "Money", opName: "add", identityName: "zero")
        let mulAssoc = makeRBSuggestion(template: "associativity", typeName: "Money", funcName: "multiply")
        let mulIdentity = makeRBIdentityElementSuggestion(typeName: "Money", opName: "multiply", identityName: "one")
        let proposals = RefactorBridgeOrchestrator.proposals(
            from: [addAssoc, addIdentity, mulAssoc, mulIdentity]
        )
        let proposal = try #require(proposals["Money"]?.first)
        // All four contributing suggestions surface in relatedIdentities.
        #expect(proposal.relatedIdentities.count == 4)
        #expect(proposal.relatedIdentities.contains(addAssoc.identity))
        #expect(proposal.relatedIdentities.contains(addIdentity.identity))
        #expect(proposal.relatedIdentities.contains(mulAssoc.identity))
        #expect(proposal.relatedIdentities.contains(mulIdentity.identity))
    }
}
