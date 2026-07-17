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

    // MARK: - Keyed (Identifiable) refint

    @Test("keyed refint: scalar-key selection over an Identifiable collection → id predicate")
    func resolvesKeyedRefint() {
        let scanned = FunctionScanner.scanCorpus(
            source: "struct Track: Identifiable { let id: Int; let title: String }",
            file: "Track.swift"
        )
        let identifiable = IdentifiableResolver(typeDecls: scanned.typeDecls)
        let viewModel = candidate([("selectedTrackID", "Int?"), ("tracks", "[Track]")])
        // Value-membership alone gates it (UUID/Int key ≠ Track element).
        #expect(ViewModelRefintResolver.resolve(viewModel) == nil)
        // The Identifiable resolver unlocks the keyed form.
        let keyed = ViewModelRefintResolver.resolve(viewModel, identifiable: identifiable)
        #expect(keyed?.predicate
            == "(probe.selectedTrackID == nil || probe.tracks.contains { $0.id == probe.selectedTrackID! })")
    }

    @Test("keyed refint requires element-name affinity (real-VM dogfood: selectedFiles ≠ [Violation])")
    func keyedRequiresAffinity() {
        let scanned = FunctionScanner.scanCorpus(
            source: "struct Violation: Identifiable { let id: UUID }",
            file: "Violation.swift"
        )
        let identifiable = IdentifiableResolver(typeDecls: scanned.typeDecls)
        // `selectedViolationId` pairs with `[Violation]` (stem "violation").
        let good = candidate([("selectedViolationId", "UUID?"), ("violations", "[Violation]")])
        let expected = "(probe.selectedViolationId == nil "
            + "|| probe.violations.contains { $0.id == probe.selectedViolationId! })"
        #expect(ViewModelRefintResolver.resolve(good, identifiable: identifiable)?.predicate == expected)
        // `selectedFiles: Set<String>` must NOT pair with `[Violation]` (no
        // affinity; would emit a type-mismatched Set<String> ⊆ Set<UUID>).
        let bad = candidate([("selectedFiles", "Set<String>"), ("violations", "[Violation]")])
        #expect(ViewModelRefintResolver.resolve(bad, identifiable: identifiable) == nil)
    }

    @Test("keyed refint gated when the collection element is not Identifiable")
    func gatesKeyedNonIdentifiable() {
        let scanned = FunctionScanner.scanCorpus(
            source: "struct Widget { let name: String }",
            file: "Widget.swift"
        )
        let identifiable = IdentifiableResolver(typeDecls: scanned.typeDecls)
        let viewModel = candidate([("selectedID", "Int?"), ("widgets", "[Widget]")])
        #expect(ViewModelRefintResolver.resolve(viewModel, identifiable: identifiable) == nil)
    }

    // MARK: - Stub emitter

    @Test("drives randomized action sequences and re-checks the invariant after every step")
    func emitsActionDrivenInvariantCheck() {
        let source = ViewModelInvariantStubEmitter.emit(
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
        // Seeded randomized multi-step sequences + per-step invariant check.
        #expect(source.contains("struct SeededRNG: RandomNumberGenerator"))
        #expect(source.contains("func findCounterexample() -> (steps: [(Int, Int)], trial: Int)?"))
        #expect(source.contains("if violates(probe) { return (steps, trial) }"))
        #expect(source.contains("func violates(_ probe: Catalog) -> Bool "
            + "{ !(probe.selected.isSubset(of: Set(probe.items))) }"))
        // The two actions become switch arms; the single-arg one indexes its candidates.
        #expect(source.contains("case 0: probe.selectAll()"))
        #expect(source.contains("let values = [0, 1, -1]; probe.toggle(values[argIndex % values.count])"))
        // Greedy shrink on failure.
        #expect(source.contains("if replayFails(candidate) { minimal = candidate }"))
        // Both the found sequence and the shrunk one are reported: SHRUNK alone
        // hides shrink migration, and the parser reads INPUT (defaulting it to
        // "(missing)" when absent).
        #expect(source.contains("print(\"VERIFY_DEFAULT_INPUT: \\(render(found.steps))\")"))
        #expect(source.contains("print(\"VERIFY_DEFAULT_SHRUNK: \\(render(minimal))\")"))
        // The real trial index, not a hardcoded 0.
        #expect(source.contains("print(\"VERIFY_DEFAULT_TRIAL: \\(found.trial)\")"))
        #expect(!source.contains("VERIFY_DEFAULT_TRIAL: 0"))
        // The action alphabet is rendered with arity so a single-arg action's
        // candidate survives into the counterexample (Ch21 §21.3.1).
        #expect(source.contains("let actionNames = [\"selectAll\", \"toggle\"]"))
        #expect(source.contains("let actionTakesArg = [false, true]"))
        // Disclosure of the gated actions.
        #expect(source.contains("Excluded (non-generatable / multi-arg): configure"))
        #expect(source.contains("VERIFY_DEFAULT_RESULT: FAIL"))
    }
}
