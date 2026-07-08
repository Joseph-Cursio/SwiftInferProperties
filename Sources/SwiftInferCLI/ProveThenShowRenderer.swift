import Foundation

/// V1.144 — the "show" half of prove-then-show. Classifies the live survey
/// records (from `verify --all-from-index`) into four honest buckets so a
/// low-confidence `Possible` pick that *passed* an executed test surfaces,
/// a proposed property that execution *disproved* is dropped, and — crucially
/// — the picks that could NOT be tested are separated out so an
/// unverifiable carrier is never mistaken for a pass.
///
/// This runs over the *live* `SurveyRecord`s, not `verify-evidence.json`,
/// because `architectural-coverage-pending` collapses to `measuredError`
/// when persisted — the unverifiable/error distinction only exists at survey
/// time.
enum ProveThenShowRenderer {

    static func render(_ records: [SwiftInferCommand.Verify.SurveyRecord]) -> String {
        guard !records.isEmpty else {
            return "No picks to verify — the index is empty. "
                + "Run `swift-infer index --target <X>` first.\n"
        }

        let proven = records.filter { $0.outcome == .measuredBothPass }
        let disproven = records.filter { $0.outcome == .measuredDefaultFails }
        let unverifiable = records.filter { $0.outcome == .architecturalCoveragePending }
        let inconclusive = records.filter {
            $0.outcome == .measuredEdgeCaseAdvisory || $0.outcome == .measuredError
        }

        var lines = ["Prove-then-show — \(records.count) pick(s) tested", ""]
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
        _ records: [SwiftInferCommand.Verify.SurveyRecord],
        marker: String,
        showCounterexample: Bool = false,
        showDetail: Bool = false
    ) -> [String] {
        guard !records.isEmpty else { return [] }
        var lines = [header]
        let sorted = records.sorted {
            ($0.carrier ?? "", $0.primaryFunctionName, $0.templateName)
                < ($1.carrier ?? "", $1.primaryFunctionName, $1.templateName)
        }
        for record in sorted {
            let carrier = record.carrier ?? "(free)"
            var line = "  \(marker) \(carrier)  \(record.templateName)  \(record.primaryFunctionName)"
            if showCounterexample, let example = record.shrunkCounterexample ?? record.counterexample {
                line += "   [counterexample: \(example)]"
            } else if showDetail, let detail = record.outcomeDetail {
                line += "   (\(detail))"
            }
            lines.append(line)
        }
        lines.append("")
        return lines
    }
}
