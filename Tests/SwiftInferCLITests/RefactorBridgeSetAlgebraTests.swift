import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

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
        let setAlgebra = try #require(list.first { $0.protocolName == "SetAlgebra" })
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
