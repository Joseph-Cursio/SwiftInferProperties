import Foundation
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// PROTOTYPE — the MVVM interaction-family surface. Maps a recognised
/// `ViewModelCandidate` (action alphabet + State surface) to candidate
/// interaction invariants across the five families, reusing the
/// idempotence witness vocabulary and precise field-shape heuristics for
/// the State-shaped families.
@Suite("ViewModelInteractionAnalyzer — MVVM interaction families (prototype)")
struct ViewModelInteractionAnalyzerTests {

    private func candidate(
        type: String = "VM",
        state: [(String, String)] = [],
        actions: [String] = []
    ) -> ViewModelCandidate {
        ViewModelCandidate(
            location: "VM.swift:1",
            typeName: type,
            observability: .observableMacro,
            stateFields: state.map { ViewModelStateField(name: $0.0, typeText: $0.1, isMutable: true) },
            actions: actions.map {
                ViewModelAction(
                    name: $0, parameterTypes: [], isAsync: false,
                    isThrows: false, mutatesStateDirectly: true
                )
            }
        )
    }

    private func families(_ result: [ViewModelInteractionCandidate]) -> Set<InteractionInvariantFamily> {
        Set(result.map(\.family))
    }

    @Test("idempotence fires on vocabulary-matching action names, not on others")
    func idempotenceFromActionNames() {
        let result = ViewModelInteractionAnalyzer.analyze(
            candidate(actions: ["selectAll", "dismiss", "setColor", "computeTotals", "load"])
        )
        let idempotent = Set(
            result.filter { $0.family == .idempotence }.flatMap(\.subjects)
        )
        // selectAll (select*), dismiss (exact), setColor (set*) match;
        // computeTotals / load do not.
        #expect(idempotent == ["selectAll()", "dismiss()", "setColor()"])
    }

    @Test("referential integrity pairs a selected* field with sibling collections")
    func referentialIntegrityFromSelection() {
        let result = ViewModelInteractionAnalyzer.analyze(
            candidate(state: [
                ("selectedID", "UUID?"),
                ("items", "[Item]")
            ])
        )
        let refint = result.filter { $0.family == .referentialIntegrity }
        #expect(refint.map(\.subjects) == [["selectedID"]])
        #expect(refint.first?.rationale.contains("items") == true)
    }

    @Test("conservation pairs a *count* Int with a sibling collection")
    func conservationFromCount() {
        let result = ViewModelInteractionAnalyzer.analyze(
            candidate(state: [
                ("itemCount", "Int"),
                ("items", "[Item]")
            ])
        )
        #expect(result.contains { $0.family == .conservation && $0.subjects == ["itemCount"] })
    }

    @Test("cardinality fires on ≥2 mutually-exclusive presentation Optionals")
    func cardinalityFromPresentationOptionals() {
        let result = ViewModelInteractionAnalyzer.analyze(
            candidate(state: [
                ("activeSheet", "SheetRoute?"),
                ("activeAlert", "AlertRoute?"),
                ("title", "String")
            ])
        )
        let cardinality = result.filter { $0.family == .cardinality }
        #expect(cardinality.count == 1)
        #expect(Set(cardinality.first?.subjects ?? []) == ["activeSheet", "activeAlert"])
    }

    @Test("biconditional fires on a Bool flag + Optional sharing a name stem")
    func biconditionalFromSharedStem() {
        let result = ViewModelInteractionAnalyzer.analyze(
            candidate(state: [
                ("isLoading", "Bool"),
                ("loadingTask", "Task<Void, Never>?")
            ])
        )
        #expect(result.contains {
            $0.family == .biconditional && Set($0.subjects) == ["isLoading", "loadingTask"]
        })
    }

    @Test("maps candidates to InteractionInvariantSuggestions at Possible (productionization)")
    func mapsToProductionSuggestions() {
        let viewModel = candidate(
            type: "InboxModel",
            state: [("selectedID", "UUID?"), ("items", "[Int]")],
            actions: ["selectAll", "dismiss"]
        )
        let suggestions = ViewModelInteractionAnalyzer.suggestions(
            for: viewModel,
            firstSeenAt: Date(timeIntervalSince1970: 0)
        )
        #expect(!suggestions.isEmpty)
        #expect(suggestions.allSatisfy { $0.tier == .possible })
        #expect(suggestions.allSatisfy { $0.reducerQualifiedName == "InboxModel" })
        #expect(suggestions.contains { $0.family == .idempotence })
        #expect(suggestions.contains { $0.family == .referentialIntegrity })
        // Self-describing provenance in the explainability block.
        #expect(suggestions.allSatisfy { $0.whySuggested.contains { $0.contains("MVVM view model") } })
    }

    @Test("no spurious cardinality on plain Bools, no biconditional without a shared stem")
    func precisionGuards() {
        // Two plain Bools (no presentation names) + an unrelated Optional:
        // cardinality must not fire (presentation-named Optionals required),
        // biconditional must not fire (no shared stem between flag + optional).
        let result = ViewModelInteractionAnalyzer.analyze(
            candidate(state: [
                ("isAnalyzing", "Bool"),
                ("showSuppressedOnly", "Bool"),
                ("currentWorkspace", "Workspace?")
            ])
        )
        #expect(!families(result).contains(.cardinality))
        #expect(!families(result).contains(.biconditional))
    }
}
