import Foundation
import SwiftInferCore

/// V1.4.1 — Pure-function renderer for `swift-infer metrics` output.
/// Aggregates a `Decisions` value into the three §17.2 metrics that
/// the existing `DecisionRecord` shape supports — acceptance rate,
/// rejection rate (false-positive proxy), and suppression rate —
/// per-template plus a tier-mix summary.
///
/// **Three-of-five MVP scope (V1.4.1).** PRD §17.2's table lists five
/// metrics; the missing two (time-to-adoption + post-acceptance
/// failure rate) require new fields on `DecisionRecord` (`surfacedAt`
/// + `firstCommitPasses`) and are deferred to v1.5+ alongside the
/// plumbing for those fields. The v1.4 plan §"Out of scope" §
/// records the deferral.
///
/// **<20-decisions advisory note.** PRD §17.2 names 20 decisions as
/// the cliff for "candidates for retirement"; templates with fewer
/// surface a `note:` line above the rows so the user doesn't over-
/// interpret low-count statistics (mirrors §3.5 conservative bias).
public enum MetricsRenderer {

    /// Aggregate per-template counts the renderer produces internally.
    /// Exposed via the `renderRows(...)` test surface so unit tests
    /// can verify the aggregation arithmetic without parsing the
    /// rendered table.
    public struct TemplateRow: Equatable, Sendable {
        public let template: String
        public let total: Int
        public let accepted: Int
        public let rejected: Int
        public let skipped: Int

        public var acceptanceRate: Double {
            total == 0 ? 0 : Double(accepted) / Double(total)
        }

        public var rejectionRate: Double {
            total == 0 ? 0 : Double(rejected) / Double(total)
        }

        public var suppressionRate: Double {
            total == 0 ? 0 : Double(skipped) / Double(total)
        }

        /// PRD §17.2 retirement-candidate cliff: < 50% acceptance after
        /// ≥ 20 decisions. The `total < 20` guard keeps low-count
        /// templates from triggering the warning prematurely.
        public var isRetirementCandidate: Bool {
            total >= 20 && acceptanceRate < 0.5
        }

        /// Below the §17.2 statistical-significance cliff. Drives the
        /// `note:` advisory line above the rendered table.
        public var isLowCount: Bool {
            total < 20
        }

        public init(
            template: String,
            total: Int,
            accepted: Int,
            rejected: Int,
            skipped: Int
        ) {
            self.template = template
            self.total = total
            self.accepted = accepted
            self.rejected = rejected
            self.skipped = skipped
        }
    }

    public struct TierRow: Equatable, Sendable {
        public let tier: Tier
        public let total: Int
        public let accepted: Int

        public var acceptanceRate: Double {
            total == 0 ? 0 : Double(accepted) / Double(total)
        }

        public init(tier: Tier, total: Int, accepted: Int) {
            self.tier = tier
            self.total = total
            self.accepted = accepted
        }
    }

    /// Internal accumulator for `templateRows(from:)`. A nominal type
    /// keeps SwiftLint's `large_tuple` rule satisfied (3-element tuples
    /// trip it).
    private struct TemplateCounts {
        var accepted: Int = 0
        var rejected: Int = 0
        var skipped: Int = 0
    }

    /// Aggregate `decisions` into per-template rows. Sorted by total
    /// count descending, then template name ascending — the high-
    /// signal templates surface first.
    public static func templateRows(from decisions: Decisions) -> [TemplateRow] {
        var byTemplate: [String: TemplateCounts] = [:]
        for record in decisions.records {
            var entry = byTemplate[record.template, default: TemplateCounts()]
            switch record.decision {
            case .accepted, .acceptedAsConformance:
                entry.accepted += 1
            case .rejected:
                entry.rejected += 1
            case .skipped:
                entry.skipped += 1
            }
            byTemplate[record.template] = entry
        }
        return byTemplate
            .map { name, counts in
                TemplateRow(
                    template: name,
                    total: counts.accepted + counts.rejected + counts.skipped,
                    accepted: counts.accepted,
                    rejected: counts.rejected,
                    skipped: counts.skipped
                )
            }
            .sorted { lhs, rhs in
                if lhs.total != rhs.total { return lhs.total > rhs.total }
                return lhs.template < rhs.template
            }
    }

    /// Aggregate `decisions` into per-tier rows. Tier order follows
    /// the canonical `Tier.allCases` order so the rendered table reads
    /// strong → likely → possible → suppressed → advisory.
    public static func tierRows(from decisions: Decisions) -> [TierRow] {
        var byTier: [Tier: (total: Int, accepted: Int)] = [:]
        for record in decisions.records {
            var entry = byTier[record.tier, default: (0, 0)]
            entry.total += 1
            if case .accepted = record.decision {
                entry.accepted += 1
            } else if case .acceptedAsConformance = record.decision {
                entry.accepted += 1
            }
            byTier[record.tier] = entry
        }
        return Tier.allCases.compactMap { tier in
            guard let entry = byTier[tier] else { return nil }
            return TierRow(tier: tier, total: entry.total, accepted: entry.accepted)
        }
    }

    /// Render the full report. `sources` is the human-readable summary
    /// of where decisions came from (e.g., `["~/calibration/swift-collections",
    /// "..."]`). `header` is rendered above the tables so the
    /// rendered output is self-describing when piped to a file.
    public static func render(
        decisions: Decisions,
        sources: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("swift-infer metrics — calibration aggregate (PRD §17.2)")
        lines.append("")
        lines.append(sourceHeader(decisionCount: decisions.records.count, sources: sources))
        lines.append("")
        lines.append(contentsOf: templateSection(rows: templateRows(from: decisions)))
        lines.append("")
        lines.append(contentsOf: tierSection(rows: tierRows(from: decisions)))
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Section helpers

    private static func sourceHeader(decisionCount: Int, sources: [String]) -> String {
        let sourceLabel = sources.count == 1 ? "source" : "sources"
        let prefix = "Decisions: \(decisionCount) across \(sources.count) \(sourceLabel)"
        if sources.isEmpty {
            return prefix
        }
        let listing = sources.enumerated().map { index, source in
            "  \(index + 1). \(source)"
        }
        return ([prefix] + listing).joined(separator: "\n")
    }

    private static func templateSection(rows: [TemplateRow]) -> [String] {
        var lines: [String] = ["Per-template adoption:"]
        if rows.isEmpty {
            lines.append("  (no decisions yet)")
            return lines
        }
        let lowCount = rows.filter(\.isLowCount).map(\.template)
        if !lowCount.isEmpty {
            let templates = lowCount.joined(separator: ", ")
            lines.append("  note: \(templates) — fewer than 20 decisions; rates are advisory.")
        }
        lines.append(templateTableHeader())
        lines.append(templateTableSeparator())
        for row in rows {
            lines.append(templateTableRow(row))
        }
        let retirement = rows.filter(\.isRetirementCandidate).map(\.template)
        if !retirement.isEmpty {
            let templates = retirement.joined(separator: ", ")
            lines.append("")
            lines.append(
                "  retirement candidates (PRD §17.2 < 50% acceptance after ≥ 20 decisions): "
                    + templates
            )
        }
        return lines
    }

    private static func tierSection(rows: [TierRow]) -> [String] {
        var lines: [String] = ["Tier-mix at decision time:"]
        if rows.isEmpty {
            lines.append("  (no decisions yet)")
            return lines
        }
        lines.append("  | Tier       | Total | Accepted | Acceptance |")
        lines.append("  |------------|------:|---------:|-----------:|")
        for row in rows {
            let label = row.tier.label.padding(toLength: 10, withPad: " ", startingAt: 0)
            let total = String(row.total).leftPadded(width: 5)
            let accepted = String(row.accepted).leftPadded(width: 8)
            let acceptance = formatPercent(row.acceptanceRate).leftPadded(width: 10)
            lines.append("  | \(label) | \(total) | \(accepted) | \(acceptance) |")
        }
        return lines
    }

    // MARK: - Template-table cells

    private static func templateTableHeader() -> String {
        "  | Template               | Total | Accepted | Rejected | Skipped | Acceptance | Rejection | Suppression |"
    }

    private static func templateTableSeparator() -> String {
        "  |------------------------|------:|---------:|---------:|--------:|-----------:|----------:|------------:|"
    }

    private static func templateTableRow(_ row: TemplateRow) -> String {
        let template = row.template.padding(toLength: 22, withPad: " ", startingAt: 0)
        let total = String(row.total).leftPadded(width: 5)
        let accepted = String(row.accepted).leftPadded(width: 8)
        let rejected = String(row.rejected).leftPadded(width: 8)
        let skipped = String(row.skipped).leftPadded(width: 7)
        let acceptance = formatPercent(row.acceptanceRate).leftPadded(width: 10)
        let rejection = formatPercent(row.rejectionRate).leftPadded(width: 9)
        let suppression = formatPercent(row.suppressionRate).leftPadded(width: 11)
        let counts = "\(total) | \(accepted) | \(rejected) | \(skipped)"
        let rates = "\(acceptance) | \(rejection) | \(suppression)"
        return "  | \(template) | \(counts) | \(rates) |"
    }

    private static func formatPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
}

private extension String {
    func leftPadded(width: Int) -> String {
        guard count < width else { return self }
        return String(repeating: " ", count: width - count) + self
    }
}
