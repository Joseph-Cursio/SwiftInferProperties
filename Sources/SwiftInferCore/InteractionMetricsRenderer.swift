import Foundation

/// V1.102 (cycle-99 calibration helper) — render
/// `InteractionDecisionsAggregator.Report` to markdown / plain-text
/// for `metrics-interaction` stdout + direct paste into the cycle-N
/// findings doc.
///
/// Two output modes:
/// - `.markdown` — pipe-delimited tables suitable for
///   `docs/calibration-cycle-N-findings.md`.
/// - `.plain` — fixed-width columns for terminal reading.
public enum InteractionMetricsRenderer {

    public enum Format: String, Sendable, CaseIterable {
        case markdown
        case plain
    }

    /// Render the per-family acceptance-rate table + the overall
    /// summary line. `sources` is the labeled list of inputs (for
    /// the rendered header — e.g., `["HandRolled", "tca-25-corpus",
    /// "tca-10-corpus"]`). `skipRateThreshold` defaults to the
    /// rubric's 30%; families exceeding it get a trailing `*` so
    /// the reader can quickly spot refinement candidates.
    public static func render(
        _ report: InteractionDecisionsAggregator.Report,
        sources: [String],
        format: Format = .markdown,
        skipRateThreshold: Double = 0.30
    ) -> String {
        switch format {
        case .markdown:
            return renderMarkdown(report, sources: sources, skipRateThreshold: skipRateThreshold)

        case .plain:
            return renderPlain(report, sources: sources, skipRateThreshold: skipRateThreshold)
        }
    }

    // MARK: - Markdown

    private static func renderMarkdown(
        _ report: InteractionDecisionsAggregator.Report,
        sources: [String],
        skipRateThreshold: Double
    ) -> String {
        var lines: [String] = []
        lines.append("## Interaction-invariant acceptance rates")
        lines.append("")
        lines.append("Sources: " + (sources.isEmpty ? "(none)" : sources.joined(separator: ", ")))
        lines.append("")
        lines.append("| Family | Accepted | AsConformance | Rejected | Skipped | Acceptance rate | Skip rate |")
        lines.append("|---|---:|---:|---:|---:|---:|---:|")
        for family in familyDisplayOrder {
            let bucket = report.bucket(for: family)
            lines.append(
                "| "
                    + familyDisplayName(family)
                    + " | \(bucket.accepted)"
                    + " | \(bucket.acceptedAsConformance)"
                    + " | \(bucket.rejected)"
                    + " | \(bucket.skipped)"
                    + " | \(formatRate(bucket.acceptanceRate))"
                    + " | \(formatRate(bucket.skipRate, flagAbove: skipRateThreshold))"
                    + " |"
            )
        }
        lines.append(
            "| **Overall**"
                + " | **\(report.overall.accepted)**"
                + " | **\(report.overall.acceptedAsConformance)**"
                + " | **\(report.overall.rejected)**"
                + " | **\(report.overall.skipped)**"
                + " | **\(formatRate(report.overall.acceptanceRate))**"
                + " | **\(formatRate(report.overall.skipRate, flagAbove: skipRateThreshold))**"
                + " |"
        )
        lines.append("")
        if anyFamilyExceedsSkipThreshold(report, threshold: skipRateThreshold) {
            lines.append(
                "_`*` marks families whose skip rate exceeds "
                    + "\(Int(skipRateThreshold * 100))%, the rubric's refinement threshold._"
            )
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Plain text

    private static func renderPlain(
        _ report: InteractionDecisionsAggregator.Report,
        sources: [String],
        skipRateThreshold: Double
    ) -> String {
        var lines: [String] = []
        lines.append("Interaction-invariant acceptance rates")
        lines.append("Sources: " + (sources.isEmpty ? "(none)" : sources.joined(separator: ", ")))
        lines.append("")
        let header = PlainRow(
            family: "Family",
            accepted: "Accepted",
            asConformance: "AsConformance",
            rejected: "Rejected",
            skipped: "Skipped",
            acceptanceRate: "AcceptanceRate",
            skipRate: "SkipRate"
        )
        let headerRendered = header.rendered
        lines.append(headerRendered)
        lines.append(String(repeating: "-", count: headerRendered.count))
        for family in familyDisplayOrder {
            let bucket = report.bucket(for: family)
            lines.append(PlainRow(
                family: familyDisplayName(family),
                bucket: bucket,
                skipRateThreshold: skipRateThreshold
            ).rendered)
        }
        lines.append(String(repeating: "-", count: headerRendered.count))
        lines.append(PlainRow(
            family: "Overall",
            bucket: report.overall,
            skipRateThreshold: skipRateThreshold
        ).rendered)
        return lines.joined(separator: "\n")
    }

    /// Fixed-width column layout for the plain-format renderer.
    /// Hoisted into a struct to keep the call site below SwiftLint's
    /// parameter-count cap and to centralize column-width constants.
    private struct PlainRow {
        let family: String
        let accepted: String
        let asConformance: String
        let rejected: String
        let skipped: String
        let acceptanceRate: String
        let skipRate: String

        init(
            family: String,
            accepted: String,
            asConformance: String,
            rejected: String,
            skipped: String,
            acceptanceRate: String,
            skipRate: String
        ) {
            self.family = family
            self.accepted = accepted
            self.asConformance = asConformance
            self.rejected = rejected
            self.skipped = skipped
            self.acceptanceRate = acceptanceRate
            self.skipRate = skipRate
        }

        init(
            family: String,
            bucket: InteractionDecisionsAggregator.Bucket,
            skipRateThreshold: Double
        ) {
            self.init(
                family: family,
                accepted: String(bucket.accepted),
                asConformance: String(bucket.acceptedAsConformance),
                rejected: String(bucket.rejected),
                skipped: String(bucket.skipped),
                acceptanceRate: InteractionMetricsRenderer.formatRate(bucket.acceptanceRate),
                skipRate: InteractionMetricsRenderer.formatRate(
                    bucket.skipRate,
                    flagAbove: skipRateThreshold
                )
            )
        }

        var rendered: String {
            InteractionMetricsRenderer.leftPad(family, 22)
                + "  " + InteractionMetricsRenderer.rightPad(accepted, 8)
                + "  " + InteractionMetricsRenderer.rightPad(asConformance, 14)
                + "  " + InteractionMetricsRenderer.rightPad(rejected, 8)
                + "  " + InteractionMetricsRenderer.rightPad(skipped, 8)
                + "  " + InteractionMetricsRenderer.rightPad(acceptanceRate, 14)
                + "  " + InteractionMetricsRenderer.rightPad(skipRate, 10)
        }
    }

    fileprivate static func leftPad(_ value: String, _ width: Int) -> String {
        if value.count >= width { return value }
        return value + String(repeating: " ", count: width - value.count)
    }

    fileprivate static func rightPad(_ value: String, _ width: Int) -> String {
        if value.count >= width { return value }
        return String(repeating: " ", count: width - value.count) + value
    }

    fileprivate static func formatRate(
        _ rate: Double?,
        flagAbove threshold: Double? = nil
    ) -> String {
        guard let rate else { return "—" }
        let percent = Int((rate * 100).rounded())
        let flag = (threshold.map { rate > $0 } ?? false) ? "*" : ""
        return "\(percent)%\(flag)"
    }

    // MARK: - Internals

    /// Fixed display order — matches the per-family share order in
    /// cycle-7's findings (idem first, then bicon, card, refint,
    /// cons). Aligns the metrics table with the cycle-N findings
    /// `per-family distribution` table for at-a-glance comparison.
    ///
    /// This explicit array is what decouples the metrics table from
    /// `InteractionInvariantFamily`'s `case`-declaration order. It is
    /// `internal` (not `private`) only so `InteractionMetricsRendererTests`
    /// can assert it stays exhaustive — an explicit-array display order is
    /// not compiler-checked for completeness.
    static let familyDisplayOrder: [InteractionInvariantFamily] = [
        .idempotence,
        .biconditional,
        .cardinality,
        .referentialIntegrity,
        .conservation
    ]

    private static func familyDisplayName(_ family: InteractionInvariantFamily) -> String {
        switch family {
        case .idempotence: return "Idempotence"
        case .biconditional: return "Biconditional"
        case .cardinality: return "Cardinality"
        case .referentialIntegrity: return "Referential Integrity"
        case .conservation: return "Conservation"
        }
    }

    private static func anyFamilyExceedsSkipThreshold(
        _ report: InteractionDecisionsAggregator.Report,
        threshold: Double
    ) -> Bool {
        for family in InteractionInvariantFamily.allCases {
            if let skipRate = report.bucket(for: family).skipRate, skipRate > threshold {
                return true
            }
        }
        return false
    }
}
