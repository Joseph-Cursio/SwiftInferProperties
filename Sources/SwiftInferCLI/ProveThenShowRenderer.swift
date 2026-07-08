import Foundation
import SwiftInferCore

/// V1.144 — the "show" half of prove-then-show. Classifies live survey records
/// into four honest buckets so a low-confidence `Possible` pick that *passed*
/// an executed test surfaces, a proposed property that execution *disproved*
/// is dropped, and — crucially — the picks that could NOT be tested are
/// separated out so an unverifiable carrier is never mistaken for a pass.
///
/// V1.148 — surface-agnostic: a row-based core renders both the algebraic
/// survey (`verify --all-from-index`) and the interaction survey
/// (`verify-interaction --all`), which share the 5-outcome vocabulary.
enum ProveThenShowRenderer {

    /// One classified row, surface-agnostic.
    struct Row: Equatable {
        let outcome: VerifyEvidenceOutcome
        let sortKey: String
        let label: String
        /// For disproven rows — a counterexample / failing witness.
        let counterexample: String?
        /// For unverifiable / inconclusive rows — the outcome detail.
        let detail: String?
    }

    // MARK: - Algebraic surface

    static func render(_ records: [SwiftInferCommand.Verify.SurveyRecord]) -> String {
        guard !records.isEmpty else {
            return "No picks to verify — the index is empty. "
                + "Run `swift-infer index --target <X>` first.\n"
        }
        return renderRows(records.map(algebraicRow))
    }

    private static func algebraicRow(_ record: SwiftInferCommand.Verify.SurveyRecord) -> Row {
        Row(
            outcome: VerifyEvidenceRecorder.evidenceOutcome(for: record.outcome),
            sortKey: "\(record.carrier ?? "")\u{1}\(record.primaryFunctionName)\u{1}\(record.templateName)",
            label: "\(record.carrier ?? "(free)")  \(record.templateName)  \(record.primaryFunctionName)",
            counterexample: record.shrunkCounterexample ?? record.counterexample,
            detail: oneLine(record.outcomeDetail)
        )
    }

    // MARK: - Interaction surface

    static func render(interactionEntries entries: [VerifyInteractionSurvey.Entry]) -> String {
        guard !entries.isEmpty else {
            return "No interaction identities to verify — none discovered in the target. "
                + "Run `swift-infer discover-interaction --target <X> --include-possible` to see them.\n"
        }
        return renderRows(entries.map(interactionRow))
    }

    private static func interactionRow(_ entry: VerifyInteractionSurvey.Entry) -> Row {
        let suggestion = entry.suggestion
        return Row(
            outcome: entry.result.outcome,
            sortKey: "\(suggestion.family.rawValue)\u{1}\(suggestion.reducerQualifiedName)",
            label: "\(suggestion.family.rawValue)  \(suggestion.reducerQualifiedName)",
            counterexample: entry.result.failingSequenceIndex.map { "failing action-sequence #\($0)" },
            detail: oneLine(entry.result.detail)
        )
    }

    /// Collapse a multi-line detail (e.g. a build-failure stderr snippet) to a
    /// single line so the row stays one line.
    private static func oneLine(_ detail: String?) -> String? {
        guard let detail else { return nil }
        let collapsed = detail
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return collapsed.isEmpty ? nil : collapsed
    }

    // MARK: - Shared core

    private static func renderRows(_ rows: [Row]) -> String {
        let proven = rows.filter { $0.outcome == .measuredBothPass }
        let disproven = rows.filter { $0.outcome == .measuredDefaultFails }
        let unverifiable = rows.filter { $0.outcome == .architecturalCoveragePending }
        let inconclusive = rows.filter {
            $0.outcome == .measuredEdgeCaseAdvisory || $0.outcome == .measuredError
        }

        var lines = ["Prove-then-show — \(rows.count) pick(s) tested", ""]
        lines.append(
            "  Proven \(proven.count) · Disproven \(disproven.count) "
                + "· Unverifiable \(unverifiable.count) · Inconclusive \(inconclusive.count)"
        )
        lines.append("")
        lines += section(
            "PROVEN — surface these (verified by an executed property test)",
            proven, marker: "✓"
        )
        lines += section(
            "DISPROVEN — drop these (execution found a counterexample)",
            disproven, marker: "✗", showCounterexample: true
        )
        lines += section(
            "UNVERIFIABLE — NOT tested, NOT a pass (no generator for the carrier)",
            unverifiable, marker: "?", showDetail: true
        )
        lines += section(
            "INCONCLUSIVE — edge-case advisory or tooling error",
            inconclusive, marker: "·", showDetail: true
        )
        return lines.joined(separator: "\n") + "\n"
    }

    private static func section(
        _ header: String,
        _ rows: [Row],
        marker: String,
        showCounterexample: Bool = false,
        showDetail: Bool = false
    ) -> [String] {
        guard !rows.isEmpty else { return [] }
        var lines = [header]
        for row in rows.sorted(by: { $0.sortKey < $1.sortKey }) {
            var line = "  \(marker) \(row.label)"
            if showCounterexample, let example = row.counterexample {
                line += "   [counterexample: \(example)]"
            } else if showDetail, let detail = row.detail {
                line += "   (\(detail))"
            }
            lines.append(line)
        }
        lines.append("")
        return lines
    }
}
