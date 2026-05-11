import Testing
import Foundation
import SwiftInferCore
@testable import SwiftInferCLI

/// V1.35.B — `swift-infer suggest-refactors` filter + render tests.
@Suite("SuggestRefactorsCommand — V1.35.B filter + render")
struct SuggestRefactorsCommandTests {

    // MARK: - Fixtures

    private static let algebraicCluster = RefactorCluster(
        typeName: "Complex",
        totalSuggestionCount: 12,
        perTemplateCounts: ["commutativity": 6, "associativity": 6],
        shape: .algebraicStructure,
        representativeFunctions: ["+(z:w:)", "*(z:w:)", "_relaxedAdd(_:_:)"]
    )

    private static let idempotenceCluster = RefactorCluster(
        typeName: "OrderedSet",
        totalSuggestionCount: 7,
        perTemplateCounts: ["idempotence": 7],
        shape: .idempotenceCluster,
        representativeFunctions: ["sort()", "_regenerateHashTable()", "_isUnique()"]
    )

    private static let smallCluster = RefactorCluster(
        typeName: "Foo",
        totalSuggestionCount: 3,
        perTemplateCounts: ["round-trip": 3],
        shape: .roundTripCluster,
        representativeFunctions: ["encode(_:)", "decode(_:)", "format(_:)"]
    )

    private static let allThree = [algebraicCluster, idempotenceCluster, smallCluster]

    // MARK: - applyFilters

    @Test("V1.35.B — no filters, --min-suggestions = 3 (default) returns all 3")
    func noFiltersDefaultThreshold() {
        let filtered = SwiftInferCommand.SuggestRefactors.applyFilters(
            Self.allThree,
            minSuggestions: 3,
            shape: nil
        )
        #expect(filtered.count == 3)
    }

    @Test("V1.35.B — --min-suggestions 5 filters out smallCluster (3)")
    func minSuggestionsFilters() {
        let filtered = SwiftInferCommand.SuggestRefactors.applyFilters(
            Self.allThree,
            minSuggestions: 5,
            shape: nil
        )
        #expect(filtered.count == 2)
        #expect(!filtered.contains(Self.smallCluster))
    }

    @Test("V1.35.B — --shape algebraicStructure returns only the algebraic cluster")
    func shapeFilter() {
        let filtered = SwiftInferCommand.SuggestRefactors.applyFilters(
            Self.allThree,
            minSuggestions: 0,
            shape: "algebraicStructure"
        )
        #expect(filtered == [Self.algebraicCluster])
    }

    @Test("V1.35.B — --shape idempotenceCluster returns only the idempotence cluster")
    func idempotenceShapeFilter() {
        let filtered = SwiftInferCommand.SuggestRefactors.applyFilters(
            Self.allThree,
            minSuggestions: 0,
            shape: "idempotenceCluster"
        )
        #expect(filtered == [Self.idempotenceCluster])
    }

    @Test("V1.35.B — unknown --shape value returns empty (no match)")
    func unknownShapeReturnsEmpty() {
        let filtered = SwiftInferCommand.SuggestRefactors.applyFilters(
            Self.allThree,
            minSuggestions: 0,
            shape: "bogusShape"
        )
        #expect(filtered.isEmpty)
    }

    @Test("V1.35.B — filters AND together")
    func filtersCombine() {
        // --min-suggestions 5 AND --shape idempotenceCluster
        let filtered = SwiftInferCommand.SuggestRefactors.applyFilters(
            Self.allThree,
            minSuggestions: 5,
            shape: "idempotenceCluster"
        )
        #expect(filtered == [Self.idempotenceCluster])
    }

    // MARK: - renderClusters

    @Test("V1.35.B — render empty list returns 'No refactor clusters match'")
    func renderEmpty() {
        let rendered = SwiftInferCommand.SuggestRefactors.renderClusters([], totalMatched: 0)
        #expect(rendered == "No refactor clusters match.\n")
    }

    @Test("V1.35.B — render 1 cluster uses singular 'cluster'")
    func renderSingular() {
        let rendered = SwiftInferCommand.SuggestRefactors.renderClusters(
            [Self.idempotenceCluster],
            totalMatched: 1
        )
        #expect(rendered.hasPrefix("1 refactor cluster found."))
    }

    @Test("V1.35.B — render N>1 uses plural 'clusters'")
    func renderPlural() {
        let rendered = SwiftInferCommand.SuggestRefactors.renderClusters(
            Self.allThree,
            totalMatched: 3
        )
        #expect(rendered.hasPrefix("3 refactor clusters found."))
    }

    @Test("V1.35.B — render includes typeName, count, shape, templates, representatives, suggestion")
    func renderIncludesAllSections() {
        let rendered = SwiftInferCommand.SuggestRefactors.renderClusters(
            [Self.algebraicCluster],
            totalMatched: 1
        )
        #expect(rendered.contains("[Complex] 12 inferred properties — algebraic-structure cluster"))
        // Tie-break sort: equal counts → name asc, so associativity before commutativity.
        #expect(rendered.contains("templates: associativity ×6, commutativity ×6"))
        #expect(rendered.contains("representatives: +(z:w:), *(z:w:), _relaxedAdd(_:_:)"))
        #expect(rendered.contains("suggestion:"))
    }

    @Test("V1.35.B — render template counts sort by count desc, then name asc for stability")
    func renderTemplateCountsStableSort() {
        let cluster = RefactorCluster(
            typeName: "Foo",
            totalSuggestionCount: 7,
            perTemplateCounts: ["commutativity": 2, "associativity": 2, "idempotence": 3],
            shape: .idempotenceCluster,
            representativeFunctions: []
        )
        let rendered = SwiftInferCommand.SuggestRefactors.renderClusters(
            [cluster],
            totalMatched: 1
        )
        // idempotence (3) first, then ties broken by name asc
        // (associativity before commutativity since "a" < "c").
        #expect(rendered.contains("templates: idempotence ×3, associativity ×2, commutativity ×2"))
    }

    // MARK: - suggestionText curated strings

    @Test("V1.35.B — algebraicStructure suggestion mentions Semigroup/Monoid")
    func algebraicSuggestionTextStable() {
        let text = SwiftInferCommand.SuggestRefactors.suggestionText(for: .algebraicStructure)
        #expect(text.contains("Semigroup / Monoid"))
        #expect(text.contains("SwiftPropertyLaws"))
    }

    @Test("V1.35.B — idempotenceCluster suggestion mentions CoW-stable")
    func idempotenceSuggestionTextStable() {
        let text = SwiftInferCommand.SuggestRefactors.suggestionText(for: .idempotenceCluster)
        #expect(text.contains("idempotent"))
        #expect(text.contains("CoW-stable"))
    }

    @Test("V1.35.B — dualStyleCluster suggestion mentions SetAlgebra")
    func dualStyleSuggestionTextStable() {
        let text = SwiftInferCommand.SuggestRefactors.suggestionText(for: .dualStyleCluster)
        #expect(text.contains("SetAlgebra"))
        #expect(text.contains("form/non-form"))
    }

    @Test("V1.35.B — roundTripCluster suggestion mentions Codec")
    func roundTripSuggestionTextStable() {
        let text = SwiftInferCommand.SuggestRefactors.suggestionText(for: .roundTripCluster)
        #expect(text.contains("codec"))
        #expect(text.contains("Codec"))
    }

    @Test("V1.35.B — generalCluster suggestion is a focused-review prompt")
    func generalSuggestionTextStable() {
        let text = SwiftInferCommand.SuggestRefactors.suggestionText(for: .generalCluster)
        #expect(text.contains("focused review"))
    }

    @Test("V1.35.B — every ClusterShape has stable curated suggestion text")
    func everyShapeHasText() {
        for shape in ClusterShape.allCases {
            let text = SwiftInferCommand.SuggestRefactors.suggestionText(for: shape)
            #expect(!text.isEmpty, "shape \(shape) has no suggestion text")
        }
    }
}
