import Foundation
import SwiftInferCore

/// V1.64.D — verify-evidence cross-reference section, extracted from
/// `MetricsRenderer.swift` in V1.72.C so the main enum body stays under
/// SwiftLint's `type_body_length` cap. The cycle-after-cycle accretion
/// of sections (V1.4.1 template + tier, V1.64.D verify-evidence, V1.71
/// time-to-adoption, V1.72.C post-acceptance-failure) pushed the main
/// enum past 250 lines; mirrors the `+TimeToAdoption` / `+PostAcceptance`
/// extraction posture.
///
/// **What this section answers (§17.2).** How does the joined verify
/// evidence distribute across each `Decision` state? An `accepted` row
/// heavy on `bothPass` and a `rejected` row heavy on `defaultFails`
/// indicate the verify signal agrees with human judgment.
///
/// V1.69 extended the join to `--decisions` aggregation mode, so the
/// table now spans the whole corpus set there too.
extension MetricsRenderer {

    /// V1.64.D — cross-reference section. Renders a "no verify
    /// evidence" sentinel when the log is empty — no `swift-infer
    /// verify` run yet, or (in `--decisions` aggregation mode) no
    /// corpus had a sibling `verify-evidence.json`.
    static func verifyEvidenceSection(
        decisions: Decisions,
        evidence: VerifyEvidenceLog
    ) -> [String] {
        var lines: [String] = ["Verify-evidence cross-reference (PRD §17.2):"]
        if evidence.records.isEmpty {
            lines.append("  (no verify evidence — run `swift-infer verify` to populate)")
            return lines
        }
        let rows = evidenceRows(decisions: decisions, evidence: evidence)
        let matched = rows.reduce(0) { $0 + $1.total }
        lines.append(
            "  \(matched) of \(decisions.records.count) decisions have verify evidence."
        )
        if rows.isEmpty {
            return lines
        }
        lines.append(
            "  | Decision              | Total | bothPass | advisory | disproven | error | pending |"
        )
        lines.append(
            "  |-----------------------|------:|---------:|---------:|----------:|------:|--------:|"
        )
        for row in rows {
            lines.append(verifyEvidenceTableRow(row))
        }
        return lines
    }

    static func verifyEvidenceTableRow(_ row: VerifyEvidenceRow) -> String {
        let decision = row.decision.rawValue.padding(toLength: 21, withPad: " ", startingAt: 0)
        let total = verifyEvidenceLeftPad(String(row.total), width: 5)
        let bothPass = verifyEvidenceLeftPad(String(row.bothPass), width: 8)
        let advisory = verifyEvidenceLeftPad(String(row.edgeCaseAdvisory), width: 8)
        let disproven = verifyEvidenceLeftPad(String(row.defaultFails), width: 9)
        let error = verifyEvidenceLeftPad(String(row.error), width: 5)
        let pending = verifyEvidenceLeftPad(String(row.architecturalCoveragePending), width: 7)
        let counts = "\(bothPass) | \(advisory) | \(disproven) | \(error) | \(pending)"
        return "  | \(decision) | \(total) | \(counts) |"
    }
}

/// File-private right-alignment pad — `MetricsRenderer.swift`'s
/// `leftPadded` String extension is `private` to that file, so this
/// section keeps its own local copy rather than widening that helper's
/// scope module-wide. Same posture as `MetricsRenderer+TimeToAdoption.swift`
/// and `MetricsRenderer+PostAcceptanceFailure.swift`.
private func verifyEvidenceLeftPad(_ value: String, width: Int) -> String {
    guard value.count < width else { return value }
    return String(repeating: " ", count: width - value.count) + value
}
