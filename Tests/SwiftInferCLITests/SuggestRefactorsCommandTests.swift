import Foundation
import PropertyLawKit
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

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

    /// The string-presence assertions above cannot see whether the claim *between*
    /// the pinned strings is true. Until 2026-09-07 the text said conformance "lets
    /// the kit verify the paired-mutation laws on every CI run" — and the kit ships
    /// no such law, so a reader who accepted the suggestion got zero coverage of the
    /// property that produced it. Same shape as the `setUnionAssociative` veto defect
    /// in `docs/measurements/protocol-coverage-law-drift.md` §3: a claim about what
    /// another tool checks, pinned by a test that only reads the claim's spelling.
    ///
    /// This one reads the kit instead. If someone adds a paired-mutation law to
    /// `PropertyLawKit`, this fails and tells you to update the curated text.
    @Test("dual-style curated text does not overclaim kit coverage")
    func dualStyleTextDoesNotOverclaimKitCoverage() {
        // Asks the linked kit for its vocabulary instead of scanning its
        // sources. The scanner this replaced was a hand-copy of the one in
        // KitCoverageLawLevelTests, which is two copies of the same regex over
        // `.build/checkouts` — and neither could see a binary dependency.
        let setAlgebraLaws = LawIdentifier.allLawNames.filter {
            $0.hasPrefix("SetAlgebra.")
        }
        #expect(!setAlgebraLaws.isEmpty, "no SetAlgebra laws in the kit's vocabulary")

        // A paired-mutation law would have to name a mutating member.
        let mutatingMembers = [
            "formUnion", "formIntersection", "subtract", "formSymmetricDifference"
        ]
        let kitHasPairedMutationLaw = setAlgebraLaws.contains { law in
            mutatingMembers.contains { law.localizedCaseInsensitiveContains($0) }
        }

        let text = SwiftInferCommand.SuggestRefactors.suggestionText(for: .dualStyleCluster)

        // Two explicit markers rather than the negation of one. A reworded text
        // that carries neither is a third state — the claim became unreadable —
        // and that should fail here rather than silently pick a side.
        let claims = text.contains("including the paired-mutation laws")
        let disclaims = text.contains("does NOT cover the paired-mutation laws")
        #expect(
            claims != disclaims,
            """
            The dual-style text no longer states its kit-coverage position in a \
            form this test can read. Say either "including the paired-mutation \
            laws" or "does NOT cover the paired-mutation laws", or update this test.
            """
        )
        let textClaimsKitCoversThem = claims

        #expect(
            kitHasPairedMutationLaw == textClaimsKitCoversThem,
            Comment(rawValue: kitHasPairedMutationLaw
                ? "The kit now ships a paired-mutation SetAlgebra law "
                  + "(\(setAlgebraLaws.sorted().joined(separator: ", "))). The curated "
                  + "dual-style text still disclaims that coverage — update it."
                : "The curated dual-style text claims the kit verifies the "
                  + "paired-mutation laws, but the kit's SetAlgebra suite ships none. "
                  + "Add the law to PropertyLawKit before making the claim.")
        )
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
