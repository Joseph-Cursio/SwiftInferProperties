import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// V1.149 — `swift-infer report` one-glance overview renderer.
@Suite("ReportRenderer — V1.149 overview")
struct ReportRendererTests {

    private func algebraic(_ template: String, tier: String) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0x\(template)\(tier)",
            templateName: template,
            typeName: "T",
            score: 50,
            tier: tier,
            primaryFunctionName: "f(_:_:)",
            location: "/x.swift:1",
            firstSeenAt: "2026-07-01T00:00:00Z",
            lastSeenAt: "2026-07-01T00:00:00Z"
        )
    }

    private func interaction(_ family: String, tier: String) -> InteractionIndexEntry {
        InteractionIndexEntry(
            identityHash: "0x\(family)\(tier)",
            family: family,
            reducerQualifiedName: "R.reduce",
            stateTypeName: "State",
            actionTypeName: "Action",
            predicate: "p",
            location: "/r.swift:1",
            moduleName: nil,
            score: 40,
            tier: tier,
            firstSeenAt: "2026-07-01T00:00:00Z",
            lastSeenAt: "2026-07-01T00:00:00Z"
        )
    }

    private func evidence(_ outcome: VerifyEvidenceOutcome) -> VerifyEvidence {
        VerifyEvidence(
            identityHash: "h\(outcome.rawValue)",
            template: "t",
            outcome: outcome,
            detail: nil,
            capturedAt: Date(timeIntervalSince1970: 1_780_000_000),
            swiftInferVersion: "1.149.0"
        )
    }

    @Test("V1.149 — empty everything renders the 'none' sections")
    func emptyReport() {
        let out = ReportRenderer.render(
            index: IndexStore.Index(updatedAt: "2026-07-01T00:00:00Z", entries: []),
            evidence: .empty,
            insights: []
        )
        #expect(out.contains("Algebraic surface — none indexed"))
        #expect(out.contains("Interaction surface — none indexed"))
        #expect(out.contains("Measured verify — no evidence yet"))
        #expect(out.contains("Cross-type structure — none"))
    }

    @Test("V1.149 — populated report shows tier breakdowns, family/template counts, verify buckets, insights")
    func populatedReport() {
        let index = IndexStore.Index(
            updatedAt: "2026-07-01T00:00:00Z",
            entries: [
                algebraic("commutativity", tier: "Verified"),
                algebraic("commutativity", tier: "Likely"),
                algebraic("round-trip", tier: "Strong")
            ],
            interactionEntries: [
                interaction("idempotence", tier: "Likely"),
                interaction("idempotence", tier: "Possible"),
                interaction("cardinality", tier: "Possible")
            ]
        )
        let log = VerifyEvidenceLog(records: [
            evidence(.measuredBothPass),
            evidence(.measuredDefaultFails),
            evidence(.architecturalCoveragePending)
        ])
        let groups = [
            InsightsGroup(structure: "commutative monoid", members: [
                InsightsMember(typeName: "Config", operationName: "merge(_:_:)", tier: "Strong", conforms: false),
                InsightsMember(typeName: "EventLog", operationName: "+(_:_:)", tier: "Strong", conforms: false)
            ])
        ]
        let out = ReportRenderer.render(index: index, evidence: log, insights: groups)

        #expect(out.contains("Algebraic surface — 3 properties"))
        #expect(out.contains("Verified 1 · Strong 1 · Likely 1"))          // tier order
        #expect(out.contains("by template: commutativity 2, round-trip 1")) // count desc
        #expect(out.contains("Interaction surface — 3 invariant(s)"))
        #expect(out.contains("by family: idempotence 2, cardinality 1"))
        #expect(out.contains("Proven 1 · Disproven 1 · Unverifiable 1 · Inconclusive 0"))
        #expect(out.contains("static func gen()"))   // hint surfaces (1 Unverifiable)
        #expect(out.contains("Cross-type structure — 1 group(s)"))
        #expect(out.contains("2 types share a commutative monoid shape (Config, EventLog)"))
    }
}
