import Foundation
import Testing
import SwiftInferCore
import SwiftInferTemplates
@testable import SwiftInferCLI

// swiftlint:disable type_body_length file_length
// M8.4.a added 7 new tests covering the CommutativeMonoid / Group /
// Semilattice promotion arms; M8.4.b.1 added 4 more for Semilattice +
// SetAlgebra secondary detection, pushing the suite past both caps.
// Suite coheres around its subject — splitting along the body limit
// would scatter orchestrator-aggregation tests across multiple files.

@Suite("RefactorBridgeOrchestrator — per-type proposal aggregation (M7.5b)")
struct RefactorBridgeOrchestratorTests {

    // MARK: - Single-arm proposals

    @Test("Associativity-only on type T → Semigroup proposal")
    func associativityAloneFiresSemigroup() {
        let suggestion = makeSuggestion(template: "associativity", typeName: "Money")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [suggestion])
        let proposal = proposals["Money"]?.first
        #expect(proposal?.protocolName == "Semigroup")
        #expect(proposal?.relatedIdentities.contains(suggestion.identity) == true)
    }

    @Test("Associativity + identity-element on same T → Monoid proposal (Monoid wins)")
    func associativityPlusIdentityElementFiresMonoid() {
        let assoc = makeSuggestion(template: "associativity", typeName: "Tally", funcName: "merge")
        let identity = makeSuggestion(template: "identity-element", typeName: "Tally", funcName: "merge")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity])
        let proposal = proposals["Tally"]?.first
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
        #expect(proposals["Money"]?.first?.protocolName == "Semigroup")
        #expect(proposals["Tally"]?.first?.protocolName == "Monoid")
    }

    @Test("Two associativity suggestions on same type still produce one Semigroup proposal")
    func multipleAssociativityOnSameTypeAggregates() {
        // Two functions on `Money` both fire associativity: e.g. `add` and `mul`.
        let add = makeSuggestion(template: "associativity", typeName: "Money", funcName: "add")
        let mul = makeSuggestion(template: "associativity", typeName: "Money", funcName: "mul")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [add, mul])
        let proposal = proposals["Money"]?.first
        #expect(proposal?.protocolName == "Semigroup")
        #expect(proposal?.relatedIdentities.count == 2)
    }

    // MARK: - Explainability

    @Test("Proposal explainability cites every contributing suggestion")
    func explainabilityListsContributors() {
        let assoc = makeSuggestion(template: "associativity", typeName: "Tally", funcName: "merge")
        let identity = makeSuggestion(template: "identity-element", typeName: "Tally", funcName: "merge")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity])
        let why = proposals["Tally"]?.first?.explainability.whySuggested ?? []
        #expect(why.contains { $0.contains("RefactorBridge claim") })
        #expect(why.contains { $0.contains("from associativity:") })
        #expect(why.contains { $0.contains("from identity-element:") })
    }

    // MARK: - Witness extraction (M7.5.a)

    @Test("Semigroup proposal carries the binary op's bare name as combineWitness")
    func semigroupCarriesCombineWitness() {
        let assoc = makeSuggestion(template: "associativity", typeName: "Money", funcName: "merge")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc])
        let proposal = proposals["Money"]?.first
        #expect(proposal?.combineWitness == "merge")
        #expect(proposal?.identityWitness == nil)
    }

    @Test("Monoid proposal carries both binary op and identity element witnesses")
    func monoidCarriesBothWitnesses() {
        let assoc = makeSuggestion(template: "associativity", typeName: "Tally", funcName: "merge")
        let identity = makeIdentityElementSuggestion(
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
        let assoc = makeSuggestion(template: "associativity", typeName: "Tally", funcName: "merge")
        // IdentityElementTemplate emits a qualified displayName like
        // `"Tally.empty"` when the identity is a static member of a
        // type. The orchestrator strips the type prefix so the witness
        // resolves correctly via `Self.<name>` inside the extension.
        let identity = makeIdentityElementSuggestion(
            typeName: "Tally",
            opName: "merge",
            identityDisplayName: "Tally.empty"
        )
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity])
        #expect(proposals["Tally"]?.first?.identityWitness == "empty")
    }

    @Test("Witness names propagate when only the identity-element suggestion contributes the binary op evidence")
    func witnessNamesFromIdentityElementAlone() {
        // Edge case: associativity is the priority signal, but if it's
        // missing entirely the orchestrator returns nil (no Semigroup
        // claim). This test confirms the witness-only-on-identity-element
        // path doesn't accidentally produce a proposal — the Semigroup
        // gate is associativity-only per open decision #6.
        let identity = makeIdentityElementSuggestion(
            typeName: "Tally",
            opName: "merge",
            identityName: "empty"
        )
        let proposals = RefactorBridgeOrchestrator.proposals(from: [identity])
        #expect(proposals["Tally"] == nil)
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

    /// Build an identity-element suggestion with the two-row evidence
    /// shape `IdentityElementTemplate.suggest` produces — operation
    /// evidence first, then identity-element evidence. The orchestrator
    /// reads evidence[0] for combineWitness, evidence[1] for
    /// identityWitness.
    private func makeIdentityElementSuggestion(
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

    // MARK: - M8.4.a — CommutativeMonoid / Group / Semilattice promotions

    @Test("Associativity + identity + commutativity → CommutativeMonoid proposal")
    func commutativeMonoidPromotion() throws {
        let assoc = makeSuggestion(template: "associativity", typeName: "Tally", funcName: "merge")
        let identity = makeIdentityElementSuggestion(typeName: "Tally", opName: "merge")
        let comm = makeSuggestion(template: "commutativity", typeName: "Tally", funcName: "merge")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity, comm])
        let proposal = try #require(proposals["Tally"]?.first)
        #expect(proposal.protocolName == "CommutativeMonoid")
        #expect(proposal.combineWitness == "merge")
        #expect(proposal.identityWitness == "empty")
        #expect(proposal.inverseWitness == nil)
    }

    @Test("Associativity + identity + inverse-element pair → Group proposal")
    func groupPromotion() throws {
        let assoc = makeSuggestion(template: "associativity", typeName: "AdditiveInt", funcName: "plus")
        let identity = makeIdentityElementSuggestion(typeName: "AdditiveInt", opName: "plus")
        let pair = makeInversePair(typeName: "AdditiveInt", opName: "plus", inverseName: "negate")
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
        let assoc = makeSuggestion(template: "associativity", typeName: "MaxInt", funcName: "max")
        let identity = makeIdentityElementSuggestion(typeName: "MaxInt", opName: "max")
        let comm = makeSuggestion(template: "commutativity", typeName: "MaxInt", funcName: "max")
        let idem = makeSuggestion(template: "idempotence", typeName: "MaxInt", funcName: "max")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity, comm, idem])
        let proposal = try #require(proposals["MaxInt"]?.first)
        #expect(proposal.protocolName == "Semilattice")
        #expect(proposal.identityWitness == "empty")
    }

    @Test("Incomparable arms (CommutativeMonoid + Group) emit both proposals (M8.4.b.1 open #6)")
    func incomparableArmsEmitBothProposals() throws {
        // Type with all four signals: assoc + identity + commutativity +
        // inverse-element. Mathematically a CommutativeGroup, but kit-side
        // CommutativeGroup is out of v1.9 scope. Per M8.4.b.1 open
        // decision #6 default `(a)`, the orchestrator emits BOTH
        // CommutativeMonoid (B) and Group (B') as peer proposals — the
        // user picks one (or both, across sessions) at the
        // `[A/B/B'/s/n/?]` extended prompt.
        let assoc = makeSuggestion(template: "associativity", typeName: "AbelianInt", funcName: "plus")
        let identity = makeIdentityElementSuggestion(typeName: "AbelianInt", opName: "plus")
        let comm = makeSuggestion(template: "commutativity", typeName: "AbelianInt", funcName: "plus")
        let pair = makeInversePair(typeName: "AbelianInt", opName: "plus", inverseName: "negate")
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
        // The M8.4.a forward-pointer ("also satisfies CommutativeMonoid")
        // is gone — both arms now surface as real proposals.
        let groupWhy = list[1].explainability.whySuggested.joined(separator: "\n")
        #expect(groupWhy.contains("M8.4.b will split incomparable arms") == false)
    }

    @Test("Inverse-element pair without associativity does NOT promote to Group")
    func inversePairAloneDoesNotPromote() throws {
        // Group requires Monoid (associativity + identity) + inverse.
        // An InverseElementPair without the Monoid signals shouldn't
        // surface a proposal at all — the type isn't structurally a Group.
        let pair = makeInversePair(typeName: "Floating", opName: "plus", inverseName: "negate")
        let proposals = RefactorBridgeOrchestrator.proposals(
            from: [],
            inverseElementPairs: [pair]
        )
        #expect(proposals.isEmpty)
    }

    @Test("Group's relatedIdentities covers the contributing Suggestions only (not the inverse pair)")
    func groupRelatedIdentitiesCoverSuggestionsOnly() throws {
        let assoc = makeSuggestion(template: "associativity", typeName: "AdditiveInt", funcName: "plus")
        let identity = makeIdentityElementSuggestion(typeName: "AdditiveInt", opName: "plus")
        let pair = makeInversePair(typeName: "AdditiveInt", opName: "plus", inverseName: "negate")
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
        let assoc = makeSuggestion(template: "associativity", typeName: "Tally", funcName: "merge")
        let identity = makeIdentityElementSuggestion(typeName: "Tally", opName: "merge")
        let comm = makeSuggestion(template: "commutativity", typeName: "Tally", funcName: "merge")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity, comm])
        let proposal = try #require(proposals["Tally"]?.first)
        let caveats = proposal.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("Commutativity is a Strict law per kit v1.9.0"))
    }

    // MARK: - M8.4.b.1 — Semilattice + SetAlgebra secondary (open #3)

    @Test("Semilattice + curated set-named op fires SetAlgebra secondary")
    func semilatticeWithUnionOpEmitsSetAlgebraSecondary() throws {
        // Type whose binary op is `union` — one of the curated SetAlgebra
        // verbs. The Semilattice signal set fires (assoc + comm + idem +
        // identity), so the orchestrator emits Semilattice (B) + SetAlgebra
        // (B') as primary + secondary.
        let assoc = makeSuggestion(template: "associativity", typeName: "Bag", funcName: "union")
        let identity = makeIdentityElementSuggestion(typeName: "Bag", opName: "union")
        let comm = makeSuggestion(template: "commutativity", typeName: "Bag", funcName: "union")
        let idem = makeSuggestion(template: "idempotence", typeName: "Bag", funcName: "union")
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
        // `max` isn't in the curated SetAlgebra-verb list — the
        // Semilattice claim alone surfaces, no secondary.
        let assoc = makeSuggestion(template: "associativity", typeName: "MaxInt", funcName: "max")
        let identity = makeIdentityElementSuggestion(typeName: "MaxInt", opName: "max")
        let comm = makeSuggestion(template: "commutativity", typeName: "MaxInt", funcName: "max")
        let idem = makeSuggestion(template: "idempotence", typeName: "MaxInt", funcName: "max")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity, comm, idem])
        let list = try #require(proposals["MaxInt"])
        #expect(list.count == 1)
        #expect(list[0].protocolName == "Semilattice")
    }

    @Test("SetAlgebra secondary carries the SetAlgebra-specific caveat")
    func setAlgebraSecondaryCarriesCaveat() throws {
        let assoc = makeSuggestion(template: "associativity", typeName: "Bag", funcName: "intersect")
        let identity = makeIdentityElementSuggestion(typeName: "Bag", opName: "intersect")
        let comm = makeSuggestion(template: "commutativity", typeName: "Bag", funcName: "intersect")
        let idem = makeSuggestion(template: "idempotence", typeName: "Bag", funcName: "intersect")
        let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity, comm, idem])
        let list = try #require(proposals["Bag"])
        let setAlgebra = try #require(list.first(where: { $0.protocolName == "SetAlgebra" }))
        let caveats = setAlgebra.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("stdlib `SetAlgebra` requires more than"))
        #expect(caveats.contains("`insert`, `remove`, `contains`"))
    }

    @Test("Every curated SetAlgebra verb triggers the secondary")
    func allCuratedSetAlgebraVerbsTrigger() throws {
        // The curated list inside TypeAccumulator.isCuratedSetAlgebraOp
        // covers union / intersect / intersection / subtract / subtracting /
        // formUnion / formIntersection / formSymmetricDifference /
        // symmetricDifference. Spot-check a representative subset.
        let representativeVerbs = ["union", "intersect", "subtract", "formUnion", "symmetricDifference"]
        for verb in representativeVerbs {
            let assoc = makeSuggestion(template: "associativity", typeName: "S", funcName: verb)
            let identity = makeIdentityElementSuggestion(typeName: "S", opName: verb)
            let comm = makeSuggestion(template: "commutativity", typeName: "S", funcName: verb)
            let idem = makeSuggestion(template: "idempotence", typeName: "S", funcName: verb)
            let proposals = RefactorBridgeOrchestrator.proposals(from: [assoc, identity, comm, idem])
            let list = try #require(proposals["S"])
            #expect(list.count == 2, "Verb '\(verb)' should fire SetAlgebra secondary")
            #expect(list.contains { $0.protocolName == "SetAlgebra" })
        }
    }

    // MARK: - M8.4.a Helpers

    private func makeInversePair(
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
}
// swiftlint:enable type_body_length file_length
