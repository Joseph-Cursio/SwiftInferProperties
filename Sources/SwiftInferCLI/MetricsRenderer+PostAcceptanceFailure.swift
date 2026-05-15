import Foundation
import SwiftInferCore

/// V1.72.C — PRD §17.2's fifth and final metric: **post-acceptance
/// failure rate**. For accepted suggestions that have been re-checked
/// by `swift-infer accept-check`, what fraction of those re-checks
/// returned `nowFails` (the property the user accepted is now
/// disproven — regression detected)?
///
/// **Denominator semantics.** The rate is `nowFails / (stillPasses +
/// nowFails)` per template. `obsolete` (function evolved past the
/// suggestion shape — informative, not a failure) and `error` (couldn't
/// measure — unsupported template / build failure / runtime error) are
/// excluded from the denominator; they're shown in their own counts so
/// the user can see *why* a re-check didn't produce a verdict.
///
/// **Why a fifth state is necessary.** The pre-acceptance verify metric
/// (V1.64.D) collapses to a 3-outcome question because the suggestion
/// always exists when verify runs. Post-acceptance, the suggestion can
/// stop existing in current source — the accepted property's function
/// changed name, was deleted, or evolved past the suggestion shape.
/// Calling that "failure" would conflate regression-of-property with
/// natural code evolution, so we route it to its own `obsolete` bucket
/// and exclude it from the rate.
///
/// **Selection bias** is the honest caveat the section surfaces in its
/// header — the rate only reflects accepted suggestions the user
/// re-checked. The section is the §17.2 metric the PRD calls for;
/// it is not a population-wide regression rate.
///
/// Extracted to its own file so `MetricsRenderer.swift`'s enum body
/// doesn't grow further — mirrors `MetricsRenderer+TimeToAdoption.swift`.
extension MetricsRenderer {

    /// Per-template post-acceptance failure summary. Counts each of
    /// the four `PostAcceptanceOutcomeKind` states + the computed
    /// rate. Rate is `nil` when the denominator is zero (no
    /// `stillPasses` + `nowFails` records for this template).
    public struct PostAcceptanceFailureRow: Equatable, Sendable {
        public let template: String
        public let stillPasses: Int
        public let nowFails: Int
        public let obsolete: Int
        public let error: Int
        public let failureRate: Double?

        public init(
            template: String,
            stillPasses: Int,
            nowFails: Int,
            obsolete: Int,
            error: Int
        ) {
            self.template = template
            self.stillPasses = stillPasses
            self.nowFails = nowFails
            self.obsolete = obsolete
            self.error = error
            let denominator = stillPasses + nowFails
            self.failureRate = denominator == 0 ? nil : Double(nowFails) / Double(denominator)
        }

        /// Total records contributing to this row (all four kinds).
        public var total: Int {
            stillPasses + nowFails + obsolete + error
        }
    }

    /// Internal accumulator for `postAcceptanceFailureRows(...)`. A
    /// nominal struct keeps SwiftLint's `large_tuple` rule satisfied —
    /// the same pattern `TemplateCounts` uses in `MetricsRenderer`.
    private struct PostAcceptanceCounts {
        var stillPasses: Int = 0
        var nowFails: Int = 0
        var obsolete: Int = 0
        var error: Int = 0
    }

    /// Join accepted decisions against post-acceptance outcomes by
    /// identity hash and aggregate per template. Sorted by total
    /// descending, then template ascending — the high-signal
    /// templates surface first.
    ///
    /// Mirrors the V1.71 `timeToAdoptionRows` join shape: only
    /// `accepted` + `acceptedAsConformance` decisions contribute, and
    /// only when there is a matching `PostAcceptanceOutcome` for the
    /// decision's identity hash. The post-acceptance file is keyed on
    /// the normalized (no-`0x`) hash, matching `DecisionRecord`, so the
    /// join is direct.
    public static func postAcceptanceFailureRows(
        decisions: Decisions,
        outcomes: PostAcceptanceOutcomeLog
    ) -> [PostAcceptanceFailureRow] {
        let outcomeByHash = Dictionary(
            outcomes.records.map { ($0.identityHash, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        var byTemplate: [String: PostAcceptanceCounts] = [:]
        for record in decisions.records {
            switch record.decision {
            case .accepted, .acceptedAsConformance:
                break
            case .rejected, .skipped:
                continue
            }
            guard let outcome = outcomeByHash[record.identityHash] else { continue }
            var entry = byTemplate[record.template, default: PostAcceptanceCounts()]
            switch outcome.outcome {
            case .stillPasses:
                entry.stillPasses += 1
            case .nowFails:
                entry.nowFails += 1
            case .obsolete:
                entry.obsolete += 1
            case .error:
                entry.error += 1
            }
            byTemplate[record.template] = entry
        }
        return byTemplate
            .map { template, counts in
                PostAcceptanceFailureRow(
                    template: template,
                    stillPasses: counts.stillPasses,
                    nowFails: counts.nowFails,
                    obsolete: counts.obsolete,
                    error: counts.error
                )
            }
            .sorted { lhs, rhs in
                if lhs.total != rhs.total { return lhs.total > rhs.total }
                return lhs.template < rhs.template
            }
    }

    /// V1.72.C — post-acceptance failure-rate section. Two sentinels:
    /// no outcomes file loaded at all (run `accept-check` to populate),
    /// or an outcomes file with no joinable records.
    ///
    /// Header surfaces two honest caveats:
    ///   1. **Selection bias.** The rate only reflects accepted
    ///      decisions the user re-checked — not a population-wide
    ///      regression rate.
    ///   2. **Denominator exclusion.** When `obsolete` records exist,
    ///      the section names the count so the reader knows what's
    ///      *not* in the denominator.
    static func postAcceptanceFailureSection(
        decisions: Decisions,
        outcomes: PostAcceptanceOutcomeLog
    ) -> [String] {
        var lines: [String] = ["Post-acceptance failure rate (PRD §17.2):"]
        if outcomes.records.isEmpty {
            lines.append("  (no post-acceptance outcomes — run `swift-infer accept-check` to populate)")
            return lines
        }
        let rows = postAcceptanceFailureRows(decisions: decisions, outcomes: outcomes)
        if rows.isEmpty {
            lines.append("  (no accepted decisions joined to a post-acceptance outcome)")
            return lines
        }
        let joined = rows.reduce(0) { $0 + $1.total }
        let obsoleteTotal = rows.reduce(0) { $0 + $1.obsolete }
        lines.append(
            "  \(joined) accepted decision\(joined == 1 ? "" : "s") joined to a post-acceptance outcome."
        )
        lines.append("  note: rate reflects only re-checked decisions — selection bias applies.")
        if obsoleteTotal > 0 {
            let plural = obsoleteTotal == 1 ? "record" : "records"
            lines.append(
                "  note: \(obsoleteTotal) `obsolete` \(plural) excluded from the rate denominator "
                    + "(function evolved past the suggestion shape — informative, not a failure)."
            )
        }
        lines.append("  | Template               | Passes | Fails | Obsolete | Error |   Rate |")
        lines.append("  |------------------------|-------:|------:|---------:|------:|-------:|")
        for row in rows {
            let template = row.template.padding(toLength: 22, withPad: " ", startingAt: 0)
            let passes = postAcceptanceLeftPad(String(row.stillPasses), width: 6)
            let fails = postAcceptanceLeftPad(String(row.nowFails), width: 5)
            let obsolete = postAcceptanceLeftPad(String(row.obsolete), width: 8)
            let error = postAcceptanceLeftPad(String(row.error), width: 5)
            let rate = postAcceptanceLeftPad(formatFailureRate(row.failureRate), width: 6)
            lines.append("  | \(template) | \(passes) | \(fails) | \(obsolete) | \(error) | \(rate) |")
        }
        return lines
    }

    /// Format a failure rate as `"NN.N%"` or `"n/a"` when the
    /// denominator was zero (no `stillPasses` + `nowFails` records
    /// for this template).
    static func formatFailureRate(_ rate: Double?) -> String {
        guard let rate else { return "n/a" }
        return String(format: "%.1f%%", rate * 100)
    }
}

/// File-private right-alignment pad — `MetricsRenderer.swift`'s
/// `leftPadded` String extension is `private` to that file, so the
/// post-acceptance section keeps its own local copy rather than
/// widening that helper's scope module-wide. Mirrors the same
/// posture as `MetricsRenderer+TimeToAdoption.swift`.
private func postAcceptanceLeftPad(_ value: String, width: Int) -> String {
    guard value.count < width else { return value }
    return String(repeating: " ", count: width - value.count) + value
}
