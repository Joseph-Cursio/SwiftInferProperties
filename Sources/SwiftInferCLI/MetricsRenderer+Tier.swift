import Foundation
import SwiftInferCore

/// V1.72.C — tier-mix section, extracted from `MetricsRenderer.swift`
/// so the main enum body stays under SwiftLint's `type_body_length`
/// cap as the V1.64.D / V1.71 / V1.72.C sections accreted. Mirrors the
/// `+TimeToAdoption` / `+VerifyEvidence` / `+PostAcceptanceFailure`
/// extraction pattern — each cycle adds a section, each section lives
/// in its own file.
extension MetricsRenderer {

    static func tierSection(rows: [TierRow]) -> [String] {
        var lines: [String] = ["Tier-mix at decision time:"]
        if rows.isEmpty {
            lines.append("  (no decisions yet)")
            return lines
        }
        lines.append("  | Tier       | Total | Accepted | Acceptance |")
        lines.append("  |------------|------:|---------:|-----------:|")
        for row in rows {
            let label = row.tier.label.padding(toLength: 10, withPad: " ", startingAt: 0)
            let total = tierLeftPad(String(row.total), width: 5)
            let accepted = tierLeftPad(String(row.accepted), width: 8)
            let acceptance = tierLeftPad(formatTierPercent(row.acceptanceRate), width: 10)
            lines.append("  | \(label) | \(total) | \(accepted) | \(acceptance) |")
        }
        return lines
    }

    static func formatTierPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
}

/// File-private right-alignment pad — same posture as the other
/// `MetricsRenderer+*` extensions: each section file keeps its own
/// copy rather than widening `MetricsRenderer.swift`'s file-private
/// `leftPadded` String extension module-wide.
private func tierLeftPad(_ value: String, width: Int) -> String {
    guard value.count < width else { return value }
    return String(repeating: " ", count: width - value.count) + value
}
