import Foundation
import SwiftInferCore

/// V1.71 — PRD §17.2's "time-to-adoption" metric: the wall-clock gap
/// between a suggestion first being surfaced and the user accepting it
/// ("long times suggest the suggestion is unclear").
///
/// **No `Decisions` schema bump was needed.** The SemanticIndex already
/// persists both anchors per entry: `firstSeenAt` (stamped on the first
/// `swift-infer index` run, preserved across upserts) and the decision
/// (mirrored from `decisions.json`). This section joins an accepted
/// `DecisionRecord` against its index entry by identity hash and
/// computes `record.timestamp − entry.firstSeenAt` — the v1.4 plan's
/// assumed `DecisionRecord.surfacedAt` field is unnecessary (and would
/// have been worse: a triage-time stamp reads ~0, since interactive
/// triage *is* the surfacing moment).
///
/// Extracted to its own file so `MetricsRenderer.swift`'s enum body
/// stays near its prior length.
extension MetricsRenderer {

    /// Per-template time-to-adoption summary over accepted decisions
    /// that joined to a SemanticIndex entry. Durations are in seconds.
    public struct TimeToAdoptionRow: Equatable, Sendable {
        public let template: String
        public let count: Int
        public let minSeconds: TimeInterval
        public let medianSeconds: TimeInterval
        public let maxSeconds: TimeInterval

        public init(
            template: String,
            count: Int,
            minSeconds: TimeInterval,
            medianSeconds: TimeInterval,
            maxSeconds: TimeInterval
        ) {
            self.template = template
            self.count = count
            self.minSeconds = minSeconds
            self.medianSeconds = medianSeconds
            self.maxSeconds = maxSeconds
        }
    }

    /// Join accepted decisions against `indexEntries` by identity hash
    /// and bucket per template. An accepted decision contributes a
    /// duration when the index has a matching entry whose `firstSeenAt`
    /// parses as an ISO8601 timestamp. The gap is clamped at 0 — a
    /// decision recorded before the first `index` run reads as "adopted
    /// instantly" rather than negative. Rows are sorted by count
    /// descending, then template ascending (matching `templateRows`).
    ///
    /// `SemanticIndexEntry.identityHash` carries the `0x`-prefixed
    /// `display` form; `DecisionRecord.identityHash` is the stripped
    /// form — `VerifyEvidenceRecorder.normalizedIdentityHash` bridges
    /// them so the join is direct.
    public static func timeToAdoptionRows(
        decisions: Decisions,
        indexEntries: [SemanticIndexEntry]
    ) -> [TimeToAdoptionRow] {
        let parser = ISO8601DateFormatter()
        let firstSeenByHash: [String: Date] = indexEntries.reduce(into: [:]) { map, entry in
            guard let date = parser.date(from: entry.firstSeenAt) else { return }
            map[VerifyEvidenceRecorder.normalizedIdentityHash(entry.identityHash)] = date
        }
        var byTemplate: [String: [TimeInterval]] = [:]
        for record in decisions.records {
            switch record.decision {
            case .accepted, .acceptedAsConformance:
                break
            case .rejected, .skipped:
                continue
            }
            guard let firstSeen = firstSeenByHash[record.identityHash] else { continue }
            let gap = max(0, record.timestamp.timeIntervalSince(firstSeen))
            byTemplate[record.template, default: []].append(gap)
        }
        return byTemplate
            .map { template, durations in
                let sorted = durations.sorted()
                return TimeToAdoptionRow(
                    template: template,
                    count: sorted.count,
                    minSeconds: sorted.first ?? 0,
                    medianSeconds: median(of: sorted),
                    maxSeconds: sorted.last ?? 0
                )
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.template < rhs.template
            }
    }

    /// Median of a pre-sorted `[TimeInterval]`. Even count → mean of the
    /// two central values; empty → 0.
    private static func median(of sorted: [TimeInterval]) -> TimeInterval {
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    /// V1.71 — time-to-adoption section. Sentinels: no SemanticIndex
    /// loaded at all (`indexEntries` empty), or an index with no
    /// accepted-and-joined decisions.
    static func timeToAdoptionSection(
        decisions: Decisions,
        indexEntries: [SemanticIndexEntry]
    ) -> [String] {
        var lines: [String] = ["Time-to-adoption (PRD §17.2):"]
        if indexEntries.isEmpty {
            lines.append("  (no SemanticIndex — run `swift-infer index` to populate)")
            return lines
        }
        let rows = timeToAdoptionRows(decisions: decisions, indexEntries: indexEntries)
        if rows.isEmpty {
            lines.append("  (no accepted decisions joined to a SemanticIndex entry)")
            return lines
        }
        let joined = rows.reduce(0) { $0 + $1.count }
        lines.append(
            "  \(joined) accepted decision\(joined == 1 ? "" : "s") joined to the index "
                + "(firstSeenAt → decision timestamp)."
        )
        lines.append("  | Template               |  Count |    Min | Median |    Max |")
        lines.append("  |------------------------|-------:|-------:|-------:|-------:|")
        for row in rows {
            let template = row.template.padding(toLength: 22, withPad: " ", startingAt: 0)
            let cells = [
                String(row.count),
                formatDuration(row.minSeconds),
                formatDuration(row.medianSeconds),
                formatDuration(row.maxSeconds)
            ].map { metricsLeftPad($0, width: 6) }
            lines.append("  | \(template) | \(cells[0]) | \(cells[1]) | \(cells[2]) | \(cells[3]) |")
        }
        return lines
    }

    /// Compact human-readable duration: seconds / minutes / hours /
    /// days, integer-truncated. Deterministic — byte-stable for tests.
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m" }
        if total < 86_400 { return "\(total / 3600)h" }
        return "\(total / 86_400)d"
    }
}

/// File-private right-alignment pad — `MetricsRenderer.swift`'s
/// `leftPadded` String extension is `private` to that file, so the
/// time-to-adoption section keeps its own local copy rather than
/// widening that helper's scope module-wide.
private func metricsLeftPad(_ value: String, width: Int) -> String {
    guard value.count < width else { return value }
    return String(repeating: " ", count: width - value.count) + value
}
