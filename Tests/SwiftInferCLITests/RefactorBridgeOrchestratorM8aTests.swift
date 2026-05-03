import Foundation
import Testing
import SwiftInferCore
import SwiftInferTemplates
@testable import SwiftInferCLI

@Suite("RefactorBridgeOrchestrator — M8.4.a CMon/Group/Semilattice promotions")
struct RefactorBridgeOrchestratorM8aTests {

    @Test("Associativity + identity + commutativity → CommutativeMonoid proposal")
    func commutativeMonoidPromotion() throws {
        let assoc = makeRBSuggestion(template: "associativity", typeName: "Tally", funcName: "merge")
        let identity = makeRBIdentityElementSuggestion(typeName: "Tally", opName: "merge")
        let comm = makeRBSuggestion(template: "commutativity", typeName: "Tally", funcName: "merge")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity, comm])
        let proposal = try #require(proposals["Tally"]?.first)
        #expect(proposal.protocolName == "CommutativeMonoid")
        #expect(proposal.combineWitness == "merge")
        #expect(proposal.identityWitness == "empty")
        #expect(proposal.inverseWitness == nil)
    }

    @Test("Associativity + identity + inverse-element pair → Group proposal")
    func groupPromotion() throws {
        let assoc = makeRBSuggestion(template: "associativity", typeName: "AdditiveInt", funcName: "plus")
        let identity = makeRBIdentityElementSuggestion(typeName: "AdditiveInt", opName: "plus")
        let pair = makeRBInversePair(typeName: "AdditiveInt", opName: "plus", inverseName: "negate")
        let proposals = RefactorBridgeOrchestrator.proposals(
            from: [assoc, identity],
            inverseElementPairs: [pair]
        )
        let proposal = try #require(proposals["AdditiveInt"]?.first)
        #expect(proposal.protocolName == "Group")
        #expect(proposal.combineWitness == "plus")
        #expect(proposal.identityWitness == "empty")
        #expect(proposal.inverseWitness == "negate")
    }

    @Test("Associativity + identity + commutativity + idempotence → Semilattice (strongest claim wins)")
    func semilatticePromotion() throws {
        let assoc = makeRBSuggestion(template: "associativity", typeName: "MaxInt", funcName: "max")
        let identity = makeRBIdentityElementSuggestion(typeName: "MaxInt", opName: "max")
        let comm = makeRBSuggestion(template: "commutativity", typeName: "MaxInt", funcName: "max")
        let idem = makeRBSuggestion(template: "idempotence", typeName: "MaxInt", funcName: "max")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity, comm, idem])
        let proposal = try #require(proposals["MaxInt"]?.first)
        #expect(proposal.protocolName == "Semilattice")
        #expect(proposal.identityWitness == "empty")
    }

    @Test("Incomparable arms (CommutativeMonoid + Group) emit both proposals (M8.4.b.1 open #6)")
    func incomparableArmsEmitBothProposals() throws {
        // Type with all four signals: assoc + identity + commutativity +
        // inverse-element. Mathematically a CommutativeGroup; kit-side
        // CommutativeGroup is out of v1.9 scope. Per M8.4.b.1 open
        // decision #6 default `(a)`, the orchestrator emits BOTH
        // CommutativeMonoid (B) and Group (B') as peer proposals.
        let assoc = makeRBSuggestion(template: "associativity", typeName: "AbelianInt", funcName: "plus")
        let identity = makeRBIdentityElementSuggestion(typeName: "AbelianInt", opName: "plus")
        let comm = makeRBSuggestion(template: "commutativity", typeName: "AbelianInt", funcName: "plus")
        let pair = makeRBInversePair(typeName: "AbelianInt", opName: "plus", inverseName: "negate")
        let proposals = RefactorBridgeOrchestrator.proposals(
            from: [assoc, identity, comm],
            inverseElementPairs: [pair]
        )
        let list = try #require(proposals["AbelianInt"])
        #expect(list.count == 2)
        // Position 0 is the primary (B) — CommutativeMonoid by the
        // alphabetical-ish ordering rule. Position 1 is Group (B').
        #expect(list[0].protocolName == "CommutativeMonoid")
        #expect(list[1].protocolName == "Group")
        #expect(list[1].inverseWitness == "negate")
        // CommutativeMonoid proposal does NOT carry the inverseWitness —
        // only Group does. Both share combine + identity witnesses.
        #expect(list[0].inverseWitness == nil)
        #expect(list[0].combineWitness == "plus")
        #expect(list[1].combineWitness == "plus")
    }

    @Test("Inverse-element pair without associativity does NOT promote to Group")
    func inversePairAloneDoesNotPromote() throws {
        // Group requires Monoid (associativity + identity) + inverse.
        let pair = makeRBInversePair(typeName: "Floating", opName: "plus", inverseName: "negate")
        let proposals = RefactorBridgeOrchestrator.proposals(
            from: [],
            inverseElementPairs: [pair]
        )
        #expect(proposals.isEmpty)
    }

    @Test("Group's relatedIdentities covers the contributing Suggestions only (not the inverse pair)")
    func groupRelatedIdentitiesCoverSuggestionsOnly() throws {
        let assoc = makeRBSuggestion(template: "associativity", typeName: "AdditiveInt", funcName: "plus")
        let identity = makeRBIdentityElementSuggestion(typeName: "AdditiveInt", opName: "plus")
        let pair = makeRBInversePair(typeName: "AdditiveInt", opName: "plus", inverseName: "negate")
        let proposals = RefactorBridgeOrchestrator.proposals(
            from: [assoc, identity],
            inverseElementPairs: [pair]
        )
        let proposal = try #require(proposals["AdditiveInt"]?.first)
        // Only the two Suggestions contribute identities — the
        // InverseElementPair has no Suggestion behind it.
        #expect(proposal.relatedIdentities.count == 2)
        #expect(proposal.relatedIdentities.contains(assoc.identity))
        #expect(proposal.relatedIdentities.contains(identity.identity))
    }

    @Test("Per-protocol caveats render in the explainability block")
    func perProtocolCaveatsRender() throws {
        let assoc = makeRBSuggestion(template: "associativity", typeName: "Tally", funcName: "merge")
        let identity = makeRBIdentityElementSuggestion(typeName: "Tally", opName: "merge")
        let comm = makeRBSuggestion(template: "commutativity", typeName: "Tally", funcName: "merge")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity, comm])
        let proposal = try #require(proposals["Tally"]?.first)
        let caveats = proposal.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("Commutativity is a Strict law per kit v1.9.0"))
    }
}
