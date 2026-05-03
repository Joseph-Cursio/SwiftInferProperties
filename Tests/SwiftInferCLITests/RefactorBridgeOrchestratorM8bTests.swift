import Foundation
import Testing
import SwiftInferCore
import SwiftInferTemplates
@testable import SwiftInferCLI

@Suite("RefactorBridgeOrchestrator — M8.4.b.1 SetAlgebra secondary")
struct RefactorBridgeSetAlgebraTests {

    @Test("Semilattice + curated set-named op fires SetAlgebra secondary")
    func semilatticeWithUnionOpEmitsSetAlgebraSecondary() throws {
        // Type whose binary op is `union` — one of the curated SetAlgebra
        // verbs. The Semilattice signal set fires (assoc + comm + idem +
        // identity), so the orchestrator emits Semilattice (B) +
        // SetAlgebra (B') as primary + secondary.
        let assoc = makeRBSuggestion(template: "associativity", typeName: "Bag", funcName: "union")
        let identity = makeRBIdentityElementSuggestion(typeName: "Bag", opName: "union")
        let comm = makeRBSuggestion(template: "commutativity", typeName: "Bag", funcName: "union")
        let idem = makeRBSuggestion(template: "idempotence", typeName: "Bag", funcName: "union")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity, comm, idem])
        let list = try #require(proposals["Bag"])
        #expect(list.count == 2)
        #expect(list[0].protocolName == "Semilattice")
        #expect(list[1].protocolName == "SetAlgebra")
        // Both proposals share the contributing-suggestion identities so
        // the prompt threads B and B' on every contributing suggestion.
        #expect(list[0].relatedIdentities == list[1].relatedIdentities)
    }

    @Test("Semilattice without curated set-named op does NOT fire SetAlgebra secondary")
    func semilatticeWithMaxOpDoesNotEmitSetAlgebra() throws {
        let assoc = makeRBSuggestion(template: "associativity", typeName: "MaxInt", funcName: "max")
        let identity = makeRBIdentityElementSuggestion(typeName: "MaxInt", opName: "max")
        let comm = makeRBSuggestion(template: "commutativity", typeName: "MaxInt", funcName: "max")
        let idem = makeRBSuggestion(template: "idempotence", typeName: "MaxInt", funcName: "max")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity, comm, idem])
        let list = try #require(proposals["MaxInt"])
        #expect(list.count == 1)
        #expect(list[0].protocolName == "Semilattice")
    }

    @Test("SetAlgebra secondary carries the SetAlgebra-specific caveat")
    func setAlgebraSecondaryCarriesCaveat() throws {
        let assoc = makeRBSuggestion(template: "associativity", typeName: "Bag", funcName: "intersect")
        let identity = makeRBIdentityElementSuggestion(typeName: "Bag", opName: "intersect")
        let comm = makeRBSuggestion(template: "commutativity", typeName: "Bag", funcName: "intersect")
        let idem = makeRBSuggestion(template: "idempotence", typeName: "Bag", funcName: "intersect")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity, comm, idem])
        let list = try #require(proposals["Bag"])
        let setAlgebra = try #require(list.first(where: { $0.protocolName == "SetAlgebra" }))
        let caveats = setAlgebra.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("stdlib `SetAlgebra` requires more than"))
        #expect(caveats.contains("`insert`, `remove`, `contains`"))
    }

    @Test("Every curated SetAlgebra verb triggers the secondary")
    func allCuratedSetAlgebraVerbsTrigger() throws {
        let representativeVerbs = ["union", "intersect", "subtract", "formUnion", "symmetricDifference"]
        for verb in representativeVerbs {
            let assoc = makeRBSuggestion(template: "associativity", typeName: "S", funcName: verb)
            let identity = makeRBIdentityElementSuggestion(typeName: "S", opName: verb)
            let comm = makeRBSuggestion(template: "commutativity", typeName: "S", funcName: verb)
            let idem = makeRBSuggestion(template: "idempotence", typeName: "S", funcName: verb)
            let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity, comm, idem])
            let list = try #require(proposals["S"])
            #expect(list.count == 2, "Verb '\(verb)' should fire SetAlgebra secondary")
            #expect(list.contains { $0.protocolName == "SetAlgebra" })
        }
    }
}

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
