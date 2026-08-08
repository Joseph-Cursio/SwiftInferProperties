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
        /// Pre-verify tier, when the caller could supply one. Drives the
        /// expected-to-hold split; `nil` leaves a refutation in DISPROVEN, which
        /// is the conservative direction.
        var tier: Tier?
        /// How much of the subject's input space the run explored.
        var coverage: RefutedExpectation.Coverage = .notApplicable
    }

    // MARK: - Algebraic surface

    /// `tiers` maps a record's identity hash to its **pre-verify** tier. Optional so
    /// every existing caller keeps compiling; without it no row can reach
    /// EXPECTED TO HOLD, which is the conservative direction — a refutation stays in
    /// DISPROVEN rather than being promoted on missing information.
    static func render(
        _ records: [SwiftInferCommand.Verify.SurveyRecord],
        tiers: [String: Tier] = [:]
    ) -> String {
        guard !records.isEmpty else {
            return "No picks to verify — the index is empty. "
                + "Run `swift-infer index --target <X>` first.\n"
        }
        return renderRows(records.map { algebraicRow($0, tier: tiers[$0.identityHash]) })
    }

    private static func algebraicRow(
        _ record: SwiftInferCommand.Verify.SurveyRecord,
        tier: Tier? = nil
    ) -> Row {
        Row(
            outcome: VerifyEvidenceRecorder.evidenceOutcome(for: record.outcome),
            sortKey: "\(record.carrier ?? "")\u{1}\(record.primaryFunctionName)\u{1}\(record.templateName)",
            label: "\(record.carrier ?? "(free)")  \(record.templateName)  \(record.primaryFunctionName)",
            counterexample: record.shrunkCounterexample ?? record.counterexample,
            detail: oneLine(record.outcomeDetail),
            tier: tier,
            // The algebraic surface has no action space to under-explore; §2.3 of the
            // scope note records that inheriting the interaction clause here would reject
            // every algebraic refutation, the four confirmed defects included.
            coverage: .notApplicable
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
            detail: oneLine(entry.result.detail),
            // Interaction rows carry no tier here on purpose: the scope note ships the
            // verdict algebraic-first, because the trap-attribution census measured a
            // 0-of-10 subject-code rate on reducer corpora — the opposite of the algebraic
            // base rate — and that census is reducer-only by its own disclosure.
            tier: nil,
            coverage: entry.result.excludedActionCount == 0 ? .full : .partial
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
        // The refutations split in two. EXPECTED TO HOLD is a VISIBILITY class, not a
        // verdict about the code: §11 measured that no static signal separates "the guess
        // was wrong" from "the code is wrong", so the section states both readings and
        // picks neither.
        let refuted = rows.filter { $0.outcome == .measuredDefaultFails }
        let expectedToHold = refuted.filter {
            RefutedExpectation.statesAFork(
                tier: $0.tier, hasCounterexample: $0.counterexample != nil, coverage: $0.coverage
            )
        }
        let disproven = refuted.filter {
            !RefutedExpectation.statesAFork(
                tier: $0.tier, hasCounterexample: $0.counterexample != nil, coverage: $0.coverage
            )
        }
        let unverifiable = rows.filter { $0.outcome == .architecturalCoveragePending }
        let inconclusive = rows.filter {
            $0.outcome == .measuredEdgeCaseAdvisory || $0.outcome == .measuredError
        }

        var lines = ["Prove-then-show — \(rows.count) pick(s) tested", ""]
        lines.append(
            "  Proven \(proven.count) · Expected-to-hold \(expectedToHold.count) "
                + "· Disproven \(disproven.count) · Unverifiable \(unverifiable.count) "
                + "· Inconclusive \(inconclusive.count)"
        )
        lines.append("")
        lines += section(
            "PROVEN — surface these (verified by an executed property test)",
            proven, marker: "✓"
        )
        lines += expectedToHoldSection(expectedToHold)
        lines += section(
            "DISPROVEN — a low-confidence guess that execution refuted",
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
        if !unverifiable.isEmpty {
            lines.append(GenHookHint.text)
            lines.append("")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The EXPECTED TO HOLD section, which differs from the others in one way that is the
    /// whole point: it renders **two readings** and does not choose.
    ///
    /// A section that said "suspected bug" would be wrong for a path join that never
    /// commuted; a section that stayed silent would be wrong for a merge fold that owes
    /// commutativity and does not deliver it. Both cases are measured, at the same tier,
    /// in `fixtures/planted-defect-arm`.
    private static func expectedToHoldSection(_ rows: [Row]) -> [String] {
        guard !rows.isEmpty else { return [] }
        var lines = [
            "EXPECTED TO HOLD, AND DOES NOT — read these first "
                + "(a high-confidence pick that execution refuted)"
        ]
        for row in rows.sorted(by: { $0.sortKey < $1.sortKey }) {
            var line = "  ! \(row.label)"
            if let example = row.counterexample {
                line += "   [counterexample: \(example)]"
            }
            lines.append(line)
        }
        lines.append("")
        lines.append("  Two readings, and this tool cannot choose between them:")
        for (index, reading) in RefutedExpectation.readings.enumerated() {
            lines.append("    \(index + 1). \(reading)")
        }
        lines.append("  \(RefutedExpectation.disclaimer)")
        lines.append("")
        return lines
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
