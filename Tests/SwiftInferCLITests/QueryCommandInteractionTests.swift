import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// V1.141 — `swift-infer query` interaction-surface filtering, surface
/// selection, and combined rendering.
@Suite("QueryCommand — V1.141 interaction surface")
struct QueryCommandInteractionTests {

    // MARK: - Fixtures

    private static let idem = InteractionIndexEntry(
        identityHash: "0x00000000000000A1",
        family: "idempotence",
        reducerQualifiedName: "NavFeature.reduce",
        stateTypeName: "State",
        actionTypeName: "Action",
        predicate: "reduce(reduce(s, .dismiss), .dismiss) == reduce(s, .dismiss)",
        location: "/nav.swift:10",
        moduleName: "Nav",
        score: 40,
        tier: "Likely",
        decision: nil,
        decisionAt: nil,
        firstSeenAt: "2026-06-13T00:00:00Z",
        lastSeenAt: "2026-06-13T12:00:00Z"
    )

    private static let refint = InteractionIndexEntry(
        identityHash: "0x00000000000000A2",
        family: "referential-integrity",
        reducerQualifiedName: "LibraryFeature.reduce",
        stateTypeName: "State",
        actionTypeName: "Action",
        predicate: "state.selectedID == nil || state.items.contains { $0.id == state.selectedID }",
        location: "/library.swift:20",
        moduleName: nil,
        score: 30,
        tier: "Possible",
        decision: "accepted",
        decisionAt: "2026-06-14T01:00:00Z",
        firstSeenAt: "2026-06-13T00:00:00Z",
        lastSeenAt: "2026-06-14T01:00:00Z"
    )

    private static let algebraic = SemanticIndexEntry(
        identityHash: "0x0000000000000001",
        templateName: "round-trip",
        typeName: "Codec",
        score: 85,
        tier: "Strong",
        primaryFunctionName: "encode(_:)",
        location: "/Codec.swift:10",
        firstSeenAt: "2026-06-10T00:00:00Z",
        lastSeenAt: "2026-06-13T12:00:00Z"
    )

    private static let bothEntries = [idem, refint]

    // MARK: - QuerySurface.parse

    @Test("V1.141 — parse nil → all, no warning")
    func parseNil() {
        let (surface, warning) = QuerySurface.parse(nil)
        #expect(surface == .all)
        #expect(warning == nil)
    }

    @Test("V1.141 — parse valid values")
    func parseValid() {
        #expect(QuerySurface.parse("algebraic").surface == .algebraic)
        #expect(QuerySurface.parse("interaction").surface == .interaction)
        #expect(QuerySurface.parse("all").surface == .all)
        #expect(QuerySurface.parse("interaction").warning == nil)
    }

    @Test("V1.141 — parse unrecognized → all + warning")
    func parseUnrecognized() {
        let (surface, warning) = QuerySurface.parse("bogus")
        #expect(surface == .all)
        #expect(warning != nil)
        #expect(warning?.contains("bogus") == true)
    }

    // MARK: - applyInteractionFilters

    @Test("V1.141 — no filter returns all interaction entries")
    func noFilter() {
        let filtered = SwiftInferCommand.Query.applyInteractionFilters(
            Self.bothEntries, filters: QueryFilters()
        )
        #expect(filtered.count == 2)
    }

    @Test("V1.141 — --family filters by family")
    func familyFilter() {
        let filtered = SwiftInferCommand.Query.applyInteractionFilters(
            Self.bothEntries, filters: QueryFilters(family: "idempotence")
        )
        #expect(filtered == [Self.idem])
    }

    @Test("V1.141 — --tier + --min-score AND together")
    func tierAndMinScore() {
        let filtered = SwiftInferCommand.Query.applyInteractionFilters(
            Self.bothEntries, filters: QueryFilters(tier: "Likely", minScore: 40)
        )
        #expect(filtered == [Self.idem])
    }

    @Test("V1.141 — --decision untriaged matches nil, 'accepted' matches recorded")
    func decisionFilter() {
        let untriaged = SwiftInferCommand.Query.applyInteractionFilters(
            Self.bothEntries, filters: QueryFilters(decision: "untriaged")
        )
        #expect(untriaged == [Self.idem])
        let accepted = SwiftInferCommand.Query.applyInteractionFilters(
            Self.bothEntries, filters: QueryFilters(decision: "accepted")
        )
        #expect(accepted == [Self.refint])
    }

    // MARK: - renderCombined

    @Test("V1.141 — renderCombined shows both sections with the interaction subheader")
    func renderBothSections() {
        let rendered = SwiftInferCommand.Query.renderCombined(
            algebraic: [Self.algebraic],
            interaction: [Self.idem],
            totalMatched: 2
        )
        #expect(rendered.hasPrefix("2 entries matched."))
        #expect(rendered.contains("[Strong 85]"))
        #expect(rendered.contains("round-trip | Codec"))
        #expect(rendered.contains("Interaction invariants:"))
        #expect(rendered.contains("[Likely 40]"))
        #expect(rendered.contains("idempotence | Nav.NavFeature.reduce"))
    }

    @Test("V1.141 — renderCombined with only interaction rows omits nothing, no leading blank section")
    func renderInteractionOnly() {
        let rendered = SwiftInferCommand.Query.renderCombined(
            algebraic: [],
            interaction: [Self.refint],
            totalMatched: 1
        )
        #expect(rendered.hasPrefix("1 entry matched."))
        #expect(rendered.contains("Interaction invariants:"))
        // moduleName nil → no module prefix on the reducer name.
        #expect(rendered.contains("referential-integrity | LibraryFeature.reduce"))
    }

    @Test("V1.141 — renderCombined with no rows returns 'No entries match'")
    func renderEmpty() {
        let rendered = SwiftInferCommand.Query.renderCombined(
            algebraic: [], interaction: [], totalMatched: 0
        )
        #expect(rendered == "No entries match.\n")
    }

    // MARK: - runQuery end-to-end (temp index on disk)

    private func withTempIndex(
        _ index: IndexStore.Index,
        _ body: (String) -> Void
    ) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("v141-query-\(UUID().uuidString)")
        let path = tempDir.appendingPathComponent("index.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try IndexStore.save(index, to: path)
        body(path.path)
    }

    @Test("V1.141 — default surface returns both algebraic + interaction rows")
    func runQueryAllSurfaces() throws {
        let index = IndexStore.Index(
            updatedAt: "2026-06-14T12:00:00Z",
            entries: [Self.algebraic],
            interactionEntries: Self.bothEntries
        )
        try withTempIndex(index) { path in
            let outcome = SwiftInferCommand.Query.runQuery(
                directoryOverride: nil,
                explicitIndexPath: path,
                filters: QueryFilters(),
                limit: nil
            )
            #expect(outcome.matchedCount == 3)
            #expect(outcome.rendered.contains("round-trip | Codec"))
            #expect(outcome.rendered.contains("Interaction invariants:"))
        }
    }

    @Test("V1.141 — --family excludes algebraic rows (interaction-only filter)")
    func runQueryFamilyExcludesAlgebraic() throws {
        let index = IndexStore.Index(
            updatedAt: "2026-06-14T12:00:00Z",
            entries: [Self.algebraic],
            interactionEntries: Self.bothEntries
        )
        try withTempIndex(index) { path in
            let outcome = SwiftInferCommand.Query.runQuery(
                directoryOverride: nil,
                explicitIndexPath: path,
                filters: QueryFilters(family: "idempotence"),
                limit: nil
            )
            #expect(outcome.matchedCount == 1)
            #expect(!outcome.rendered.contains("round-trip"))
            #expect(outcome.rendered.contains("idempotence"))
        }
    }

    @Test("V1.141 — --template excludes interaction rows (algebraic-only filter)")
    func runQueryTemplateExcludesInteraction() throws {
        let index = IndexStore.Index(
            updatedAt: "2026-06-14T12:00:00Z",
            entries: [Self.algebraic],
            interactionEntries: Self.bothEntries
        )
        try withTempIndex(index) { path in
            let outcome = SwiftInferCommand.Query.runQuery(
                directoryOverride: nil,
                explicitIndexPath: path,
                filters: QueryFilters(template: "round-trip"),
                limit: nil
            )
            #expect(outcome.matchedCount == 1)
            #expect(!outcome.rendered.contains("Interaction invariants:"))
        }
    }

    @Test("V1.141 — --surface interaction returns only interaction rows")
    func runQuerySurfaceInteraction() throws {
        let index = IndexStore.Index(
            updatedAt: "2026-06-14T12:00:00Z",
            entries: [Self.algebraic],
            interactionEntries: Self.bothEntries
        )
        try withTempIndex(index) { path in
            let outcome = SwiftInferCommand.Query.runQuery(
                directoryOverride: nil,
                explicitIndexPath: path,
                filters: QueryFilters(surface: .interaction),
                limit: nil
            )
            #expect(outcome.matchedCount == 2)
            #expect(!outcome.rendered.contains("round-trip"))
            #expect(outcome.rendered.contains("Interaction invariants:"))
        }
    }
}
