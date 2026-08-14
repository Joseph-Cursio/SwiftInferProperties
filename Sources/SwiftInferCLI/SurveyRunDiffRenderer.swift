import Foundation

/// Renders a `SurveyRunDiff.Result` for a human reading two runs side by side.
///
/// **The empty case is the load-bearing one.** A survey that reproduces its predecessor
/// exactly is a *result* — §10.1 recorded a bucket-for-bucket identical run as "the correct
/// result and ... a control, not a null" — so the report says so in as many words rather than
/// printing nothing and letting silence stand in for agreement. Silence is what a broken diff
/// also produces.
enum SurveyRunDiffRenderer {

    static func render(
        _ result: SurveyRunDiff.Result,
        before: RetainedSurveyRun,
        after: RetainedSurveyRun
    ) -> String {
        var lines: [String] = ["Survey run diff", ""]
        lines.append("  before  \(before.label)")
        lines.append("          \(before.subjectRevision)")
        lines.append("  after   \(after.label)")
        lines.append("          \(after.subjectRevision)")
        lines.append("")

        if let mismatch = result.targetMismatch {
            lines.append(
                "  ⚠ these runs surveyed DIFFERENT targets — '\(mismatch.before)' then "
                    + "'\(mismatch.after)'. Rows are keyed on suggestion identity, which is "
                    + "target-independent, so this comparison is almost certainly not the one "
                    + "you meant."
            )
            lines.append("")
        }

        lines += bucketTable(result)
        lines.append("")

        if result.isEmpty {
            lines.append(
                "  No row changed bucket or cause, and no row was added or removed. The runs "
                    + "are identical at row level — a control, not an absence of information."
            )
            lines.append("")
            return lines.joined(separator: "\n") + "\n"
        }

        lines += changedSection(result.changed)
        lines += rowListSection(
            "ADDED — picks this run tested that the earlier one did not",
            result.added
        )
        lines += rowListSection(
            "REMOVED — picks the earlier run tested that this one did not",
            result.removed
        )
        return lines.joined(separator: "\n") + "\n"
    }

    private static func bucketTable(_ result: SurveyRunDiff.Result) -> [String] {
        var lines = ["  bucket          before   after"]
        let order: [SurveyRunDiff.Bucket] = [.proven, .refuted, .unverifiable, .inconclusive]
        for bucket in order {
            let before = result.beforeCounts[bucket] ?? 0
            let after = result.afterCounts[bucket] ?? 0
            let marker = before == after ? " " : "*"
            let name = bucket.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)
            lines.append(
                "  \(name)  \(pad(before, 6))   \(pad(after, 5)) \(marker)"
            )
        }
        return lines
    }

    private static func changedSection(_ rows: [SurveyRunDiff.ChangedRow]) -> [String] {
        guard !rows.isEmpty else { return [] }
        let causeOnly = rows.filter(\.isCauseOnly).count
        var lines = [
            "CHANGED — \(rows.count) row(s), of which \(causeOnly) kept the same bucket and "
                + "changed only the cause"
        ]
        // Cause-only rows lead, because they are the ones a bucket-count comparison cannot
        // see and are therefore the reason this tool exists.
        for row in rows.sorted(by: { ($0.isCauseOnly ? 0 : 1) < ($1.isCauseOnly ? 0 : 1) }) {
            let transition = row.isCauseOnly
                ? "\(row.beforeBucket.rawValue) (cause changed)"
                : "\(row.beforeBucket.rawValue) → \(row.afterBucket.rawValue)"
            lines.append("  \(row.subject)  \(row.template)  [\(transition)]")
            lines.append("      was: \(row.beforeDetail ?? "(no detail)")")
            lines.append("      now: \(row.afterDetail ?? "(no detail)")")
            lines.append("      \(row.movement.rawValue)")
        }
        lines.append("")
        return lines
    }

    private static func rowListSection(
        _ heading: String,
        _ records: [SwiftInferCommand.Verify.SurveyRecord]
    ) -> [String] {
        guard !records.isEmpty else { return [] }
        var lines = ["\(heading) — \(records.count)"]
        for record in records {
            let bucket = SurveyRunDiff.Bucket.of(record.outcome).rawValue
            lines.append("  \(record.primaryFunctionName)  \(record.templateName)  [\(bucket)]")
        }
        lines.append("")
        return lines
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        guard text.count < width else { return text }
        return String(repeating: " ", count: width - text.count) + text
    }
}
