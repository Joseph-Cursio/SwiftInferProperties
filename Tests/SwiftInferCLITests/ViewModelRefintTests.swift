@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// PROTOTYPE — the referential-integrity pairing resolver + verifier stub.
@Suite("ViewModelRefintResolver + stub (prototype)")
struct ViewModelRefintTests {

    private func candidate(_ state: [(String, String)]) -> ViewModelCandidate {
        ViewModelCandidate(
            location: "VM.swift:1",
            typeName: "VM",
            observability: .observableObject,
            stateFields: state.map { ViewModelStateField(name: $0.0, typeText: $0.1, isMutable: true) },
            actions: []
        )
    }

    // MARK: - Resolver

    @Test("Set selection over an array collection → subset predicate")
    func resolvesSetSubset() {
        let resolved = ViewModelRefintResolver.resolve(
            candidate([("selected", "Set<Int>"), ("items", "[Int]")])
        )
        #expect(resolved?.predicate == "probe.selected.isSubset(of: Set(probe.items))")
    }

    @Test("Optional scalar selection over a collection → membership-or-nil predicate")
    func resolvesOptionalMembership() {
        let resolved = ViewModelRefintResolver.resolve(
            candidate([("selectedItem", "Int?"), ("items", "[Int]")])
        )
        #expect(resolved?.predicate
            == "(probe.selectedItem == nil || Set(probe.items).contains(probe.selectedItem!))")
    }

    @Test("mismatched element types (keyed selection) are gated — Identifiable form deferred")
    func gatesMismatchedElementType() {
        // selectedID: UUID? referencing items: [Item] by \.id — selection
        // element (UUID) ≠ collection element (Item) → not value-membership.
        #expect(ViewModelRefintResolver.resolve(
            candidate([("selectedID", "UUID?"), ("items", "[Item]")])
        ) == nil)
    }

    @Test("no sibling collection → no pairing")
    func gatesNoCollection() {
        #expect(ViewModelRefintResolver.resolve(
            candidate([("selectedItem", "Int?"), ("title", "String")])
        ) == nil)
    }

    // MARK: - Stub emitter

    @Test("drives each action and re-checks the invariant after every step")
    func emitsActionDrivenInvariantCheck() {
        let source = ViewModelRefintStubEmitter.emit(
            .init(
                typeName: "Catalog",
                predicate: "probe.selected.isSubset(of: Set(probe.items))",
                drivers: [
                    .init(name: "selectAll", label: nil, valuesExpression: nil),
                    .init(name: "toggle", label: nil, valuesExpression: "[0, 1, -1]")
                ],
                excludedActions: ["configure"]
            )
        )
        #expect(source.contains("let probe = Catalog()"))
        // Initial + per-step invariant checks.
        #expect(source.contains("if !(probe.selected.isSubset(of: Set(probe.items))) { return false }"))
        #expect(source.contains("probe.selectAll()"))
        #expect(source.contains("for arg in [0, 1, -1]"))
        #expect(source.contains("probe.toggle(arg)"))
        // Disclosure of the gated actions.
        #expect(source.contains("Excluded (non-generatable / multi-arg): configure"))
        #expect(source.contains("VERIFY_DEFAULT_RESULT: FAIL"))
    }
}
