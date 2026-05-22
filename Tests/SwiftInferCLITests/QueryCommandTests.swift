import Testing
import Foundation
import SwiftInferCore
@testable import SwiftInferCLI

/// V1.33.D — `swift-infer query` subcommand filter + render tests.
@Suite("QueryCommand — V1.33.D filter + render")
struct QueryCommandTests {

    // MARK: - Fixtures

    private static let strong = SemanticIndexEntry(
        identityHash: "0x0000000000000001",
        templateName: "round-trip",
        typeName: "Codec",
        score: 85,
        tier: "Strong",
        primaryFunctionName: "encode(_:)",
        location: "/Codec.swift:10",
        decision: "accepted",
        decisionAt: "2026-05-11T10:00:00Z",
        firstSeenAt: "2026-05-10T00:00:00Z",
        lastSeenAt: "2026-05-11T12:00:00Z"
    )

    private static let possibleSorter = SemanticIndexEntry(
        identityHash: "0x0000000000000002",
        templateName: "idempotence",
        typeName: "Sorter",
        score: 35,
        tier: "Possible",
        primaryFunctionName: "sort()",
        location: "/Sorter.swift:5",
        decision: nil,
        decisionAt: nil,
        firstSeenAt: "2026-05-11T12:00:00Z",
        lastSeenAt: "2026-05-11T12:00:00Z"
    )

    private static let possibleFreeFunc = SemanticIndexEntry(
        identityHash: "0x0000000000000003",
        templateName: "round-trip",
        typeName: nil,
        score: 30,
        tier: "Possible",
        primaryFunctionName: "log(_:)",
        location: "/Math.swift:1",
        decision: "rejected",
        decisionAt: "2026-05-11T11:00:00Z",
        firstSeenAt: "2026-05-11T00:00:00Z",
        lastSeenAt: "2026-05-11T12:00:00Z"
    )

    private static let allThree = [strong, possibleSorter, possibleFreeFunc]

    // MARK: - applyFilters

    @Test("V1.33.D — no filter returns all entries")
    func noFilterReturnsAll() {
        let filtered = SwiftInferCommand.Query.applyFilters(
            Self.allThree,
            filters: QueryFilters(template: nil, type: nil, tier: nil, decision: nil, minScore: nil
        )
        )
        #expect(filtered.count == 3)
    }

    @Test("V1.33.D — --template round-trip filters to 2 entries")
    func templateFilter() {
        let filtered = SwiftInferCommand.Query.applyFilters(
            Self.allThree,
            filters: QueryFilters(template: "round-trip", type: nil, tier: nil, decision: nil, minScore: nil
        )
        )
        #expect(filtered.count == 2)
        #expect(filtered.allSatisfy { $0.templateName == "round-trip" })
    }

    @Test("V1.33.D — --tier Strong filters to 1 entry")
    func tierFilter() {
        let filtered = SwiftInferCommand.Query.applyFilters(
            Self.allThree,
            filters: QueryFilters(template: nil, type: nil, tier: "Strong", decision: nil, minScore: nil
        )
        )
        #expect(filtered == [Self.strong])
    }

    @Test("V1.33.D — --decision untriaged matches nil decisions")
    func decisionUntriagedMatchesNil() {
        let filtered = SwiftInferCommand.Query.applyFilters(
            Self.allThree,
            filters: QueryFilters(template: nil, type: nil, tier: nil, decision: "untriaged", minScore: nil
        )
        )
        #expect(filtered == [Self.possibleSorter])
    }

    @Test("V1.33.D — --decision rejected filters to entries with decision == 'rejected'")
    func decisionRejectedFilters() {
        let filtered = SwiftInferCommand.Query.applyFilters(
            Self.allThree,
            filters: QueryFilters(template: nil, type: nil, tier: nil, decision: "rejected", minScore: nil
        )
        )
        #expect(filtered == [Self.possibleFreeFunc])
    }

    @Test("V1.33.D — --type none filters to entries with nil typeName")
    func typeNoneFiltersFreeFunctions() {
        let filtered = SwiftInferCommand.Query.applyFilters(
            Self.allThree,
            filters: QueryFilters(template: nil, type: "none", tier: nil, decision: nil, minScore: nil
        )
        )
        #expect(filtered == [Self.possibleFreeFunc])
    }

    @Test("V1.33.D — --type Codec filters by exact typeName")
    func typeExactMatch() {
        let filtered = SwiftInferCommand.Query.applyFilters(
            Self.allThree,
            filters: QueryFilters(template: nil, type: "Codec", tier: nil, decision: nil, minScore: nil
        )
        )
        #expect(filtered == [Self.strong])
    }

    @Test("V1.33.D — --min-score 50 filters to score >= 50")
    func minScoreFilter() {
        let filtered = SwiftInferCommand.Query.applyFilters(
            Self.allThree,
            filters: QueryFilters(template: nil, type: nil, tier: nil, decision: nil, minScore: 50
        )
        )
        #expect(filtered == [Self.strong])
    }

    @Test("V1.33.D — flag combinations AND together")
    func combinedFiltersAndTogether() {
        // --template round-trip AND --tier Possible → matches only the free-func entry
        let filtered = SwiftInferCommand.Query.applyFilters(
            Self.allThree,
            filters: QueryFilters(
                template: "round-trip",
                type: nil,
                tier: "Possible",
                decision: nil,
                minScore: nil
            )
        )
        #expect(filtered == [Self.possibleFreeFunc])
    }

    // MARK: - renderEntries

    @Test("V1.33.D — renderEntries on empty list returns 'No entries match'")
    func renderEmpty() {
        let rendered = SwiftInferCommand.Query.renderEntries([], totalMatched: 0)
        #expect(rendered == "No entries match.\n")
    }

    @Test("V1.33.D — renderEntries on 1 entry uses singular 'entry'")
    func renderSingularEntry() {
        let rendered = SwiftInferCommand.Query.renderEntries([Self.strong], totalMatched: 1)
        #expect(rendered.hasPrefix("1 entry matched."))
    }

    @Test("V1.33.D — renderEntries on N>1 uses plural 'entries'")
    func renderPluralEntries() {
        let rendered = SwiftInferCommand.Query.renderEntries(Self.allThree, totalMatched: 3)
        #expect(rendered.hasPrefix("3 entries matched."))
    }

    @Test("V1.33.D — render includes tier, score, template, type, name, location")
    func renderIncludesAllColumns() {
        let rendered = SwiftInferCommand.Query.renderEntries([Self.strong], totalMatched: 1)
        #expect(rendered.contains("[Strong 85]"))
        #expect(rendered.contains("round-trip"))
        #expect(rendered.contains("Codec"))
        #expect(rendered.contains("encode(_:)"))
        #expect(rendered.contains("/Codec.swift:10"))
    }

    @Test("V1.33.D — render shows '(none)' for nil typeName")
    func renderShowsNoneForFreeFunc() {
        let rendered = SwiftInferCommand.Query.renderEntries([Self.possibleFreeFunc], totalMatched: 1)
        #expect(rendered.contains("| (none) |"))
    }

    @Test("V1.33.D — render shows 'untriaged' for nil decision")
    func renderShowsUntriagedForNilDecision() {
        let rendered = SwiftInferCommand.Query.renderEntries([Self.possibleSorter], totalMatched: 1)
        #expect(rendered.contains("decision: untriaged"))
    }
}
