import Foundation
import SwiftInferCore

/// V1.149 — `swift-infer report`: a read-only, one-glance overview of what the
/// tool knows about a project, folding the SemanticIndex (algebraic +
/// interaction), the measured-verify evidence, and the cross-type insights
/// into a single status view. Pure; the command does the loading.
enum ReportRenderer {

    private static let tierOrder = ["Verified", "Strong", "Likely", "Possible", "Advisory", "Suppressed"]

    static func render(
        index: IndexStore.Index,
        evidence: VerifyEvidenceLog,
        insights: [InsightsGroup]
    ) -> String {
        var lines = ["SwiftInfer report  (index updated \(index.updatedAt))", ""]
        lines += algebraicSection(index.entries)
        lines += interactionSection(index.interactionEntries)
        lines += verifySection(evidence)
        lines += insightsSection(insights)
        lines.append("Detail: `swift-infer query` · `insights` · `prove-then-show`")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Sections

    private static func algebraicSection(_ entries: [SemanticIndexEntry]) -> [String] {
        guard !entries.isEmpty else { return ["Algebraic surface — none indexed", ""] }
        return [
            "Algebraic surface — \(entries.count) propert\(entries.count == 1 ? "y" : "ies")",
            "  " + tierBreakdown(entries.map(\.tier)),
            "  by template: " + countBreakdown(entries.map(\.templateName)),
            ""
        ]
    }

    private static func interactionSection(_ entries: [InteractionIndexEntry]) -> [String] {
        guard !entries.isEmpty else { return ["Interaction surface — none indexed", ""] }
        return [
            "Interaction surface — \(entries.count) invariant(s)",
            "  " + tierBreakdown(entries.map(\.tier)),
            "  by family: " + countBreakdown(entries.map(\.family)),
            ""
        ]
    }

    private static func verifySection(_ evidence: VerifyEvidenceLog) -> [String] {
        guard !evidence.records.isEmpty else {
            return ["Measured verify — no evidence yet (run `swift-infer verify --all-from-index`)", ""]
        }
        func count(_ outcome: VerifyEvidenceOutcome) -> Int {
            evidence.records.filter { $0.outcome == outcome }.count
        }
        let inconclusive = count(.measuredEdgeCaseAdvisory) + count(.measuredError)
        return [
            "Measured verify — \(evidence.records.count) record(s)",
            "  Proven \(count(.measuredBothPass)) · Disproven \(count(.measuredDefaultFails)) "
                + "· Unverifiable \(count(.architecturalCoveragePending)) · Inconclusive \(inconclusive)",
            ""
        ]
    }

    private static func insightsSection(_ groups: [InsightsGroup]) -> [String] {
        guard !groups.isEmpty else {
            return ["Cross-type structure — none (need ≥2 types sharing a Strong/Likely shape)", ""]
        }
        var lines = ["Cross-type structure — \(groups.count) group(s)"]
        for group in groups {
            let members = group.members.map(\.typeName).joined(separator: ", ")
            lines.append("  ▸ \(group.members.count) types share a \(group.structure) shape (\(members))")
        }
        lines.append("")
        return lines
    }

    // MARK: - Helpers

    private static func tierBreakdown(_ tiers: [String]) -> String {
        var counts: [String: Int] = [:]
        for tier in tiers { counts[tier, default: 0] += 1 }
        let parts = tierOrder.compactMap { tier -> String? in
            let count = counts[tier] ?? 0
            return count == 0 ? nil : "\(tier) \(count)"
        }
        return parts.isEmpty ? "(no tiers)" : parts.joined(separator: " · ")
    }

    private static func countBreakdown(_ names: [String], limit: Int = 8) -> String {
        var counts: [String: Int] = [:]
        for name in names { counts[name, default: 0] += 1 }
        let ordered = counts.sorted { left, right in
            left.value != right.value ? left.value > right.value : left.key < right.key
        }
        let shown = ordered.prefix(limit).map { "\($0.key) \($0.value)" }
        let extra = ordered.count > limit ? ", +\(ordered.count - limit) more" : ""
        return shown.joined(separator: ", ") + extra
    }
}
