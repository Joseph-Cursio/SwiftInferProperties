import SwiftInferCLI
import SwiftInferCore
import Testing

/// PROTOTYPE — predicate resolvers for the cardinality / biconditional /
/// conservation state-invariant families.
@Suite("ViewModel invariant resolvers (prototype)")
struct ViewModelInvariantResolversTests {

    private func candidate(_ state: [(String, String)]) -> ViewModelCandidate {
        ViewModelCandidate(
            location: "VM.swift:1",
            typeName: "VM",
            observability: .observableObject,
            stateFields: state.map { ViewModelStateField(name: $0.0, typeText: $0.1, isMutable: true) },
            actions: []
        )
    }

    @Test("cardinality: ≥2 presentation Optionals → mutual-exclusion predicate")
    func cardinality() {
        let predicate = ViewModelCardinalityResolver.resolve(
            candidate([("activeSheet", "Int?"), ("activeAlert", "Int?"), ("title", "String")])
        )
        #expect(predicate == "[(probe.activeSheet != nil), (probe.activeAlert != nil)].filter { $0 }.count <= 1")
        // A single presentation route does not fire.
        #expect(ViewModelCardinalityResolver.resolve(candidate([("activeSheet", "Int?")])) == nil)
    }

    @Test("biconditional: Bool flag + Optional sharing a stem → iff predicate")
    func biconditional() {
        let predicate = ViewModelBiconditionalResolver.resolve(
            candidate([("isActive", "Bool"), ("activeToken", "String?")])
        )
        #expect(predicate == "probe.isActive == (probe.activeToken != nil)")
        // No shared stem → no pairing.
        #expect(ViewModelBiconditionalResolver.resolve(
            candidate([("isActive", "Bool"), ("workspace", "Workspace?")])
        ) == nil)
    }

    @Test("conservation: *count* Int + collection → equality predicate")
    func conservation() {
        let predicate = ViewModelConservationResolver.resolve(
            candidate([("items", "[Int]"), ("itemCount", "Int")])
        )
        #expect(predicate == "probe.itemCount == probe.items.count")
        // No count field → no pairing.
        #expect(ViewModelConservationResolver.resolve(
            candidate([("items", "[Int]"), ("title", "String")])
        ) == nil)
    }
}
