import Foundation

/// Renders the corpus registry and its pin status.
///
/// **The summary line always states the denominator.** "Every corpus is at its pin" is a
/// different claim from "every corpus I could read is at its pin", and on a machine holding
/// three of twenty clones the second is the only true one. A report that collapses them is the
/// confident zero this repo keeps re-finding — `scanIsNotEmpty` asserting a denominator,
/// `make docs-drift` reporting a behind-by-N clone as its own fact, `DeferralFalsifierTests`
/// answering `unavailable` rather than "absent".
enum CorpusStatusRenderer {

    static func render(_ statuses: [CorpusStatus], apparatus: String? = nil) -> String {
        var lines = [heading(apparatus), ""]
        if statuses.isEmpty {
            lines.append(contentsOf: emptyBody(apparatus))
            return lines.joined(separator: "\n") + "\n"
        }
        for status in statuses {
            lines.append(contentsOf: block(for: status))
        }
        lines.append(summary(statuses))
        return lines.joined(separator: "\n") + "\n"
    }

    private static func heading(_ apparatus: String?) -> String {
        guard let apparatus else { return "Corpora — \(CorpusManifest.relativePath)" }
        return "Corpora measured by '\(apparatus)' — \(CorpusManifest.relativePath)"
    }

    /// An empty selection is reported as *measuring nothing*, never as agreement — and a
    /// filtered empty selection says which filter emptied it, because "no corpora" and "no
    /// corpora matching this apparatus" send a reader to different places.
    private static func emptyBody(_ apparatus: String?) -> [String] {
        guard let apparatus else {
            return [
                "  (the manifest lists no corpora)",
                "",
                "0 corpora. An empty corpus is not a clean sweep — nothing was measured."
            ]
        }
        return [
            "  (no corpus records a measurement by '\(apparatus)')",
            "",
            "0 corpora matched. That is a gap in coverage, not a clean sweep."
        ]
    }

    private static func block(for status: CorpusStatus) -> [String] {
        let entry = status.entry
        let reach = entry.target.map { "target \($0)" } ?? "sources \(entry.sources ?? "?")"
        var lines = [
            "  \(entry.id)  —  \(entry.subject), \(reach)  [\(entry.kind) · \(entry.role)]",
            "    pin      \(describe(status.pin))",
            "    remote   \(entry.remote)",
            "    path     \(status.checkout.path)"
        ]
        lines.append(contentsOf: measurementLines(entry))
        lines.append("    why      \(entry.why)")
        lines.append("")
        return lines
    }

    private static func measurementLines(_ entry: CorpusManifest.Entry) -> [String] {
        guard !entry.measurements.isEmpty else {
            return ["    (no measurement — registered, never measured)"]
        }
        return entry.measurements.map { measurement in
            let expectation = measurement.expectedOutcome == nil ? "" : "  [expected outcome]"
            return "    \(measurement.apparatus)/\(measurement.kind)  \(measurement.takenOn)  "
                + "\(short(measurement.revision))  \(measurement.arm)\(expectation)"
        }
    }

    private static func describe(_ pin: CorpusPin) -> String {
        switch pin {
        case .noBaseline:
            return "no baseline — nothing to compare a run here against"

        case .uncheckable:
            return "COULD NOT CHECK — no readable git checkout at the path below"

        case let .atPin(dirty):
            return dirty
                ? "at pin, but the tree is DIRTY — a run here measures uncommitted work"
                : "at pin"

        case let .movedOff(head, pinned, dirty):
            let suffix = dirty ? ", and DIRTY" : ""
            return "MOVED OFF — head \(short(head)), baseline taken at \(short(pinned))\(suffix)"
        }
    }

    /// A summary that can never read as a pass it did not earn.
    private static func summary(_ statuses: [CorpusStatus]) -> String {
        let total = statuses.count
        let uncheckable = statuses.filter { $0.pin == .uncheckable }.count
        let noBaseline = statuses.filter { $0.pin == .noBaseline }.count
        let comparable = statuses.filter(\.pin.isComparable).count
        let checked = total - uncheckable
        let noun = total == 1 ? "corpus" : "corpora"
        var parts = ["\(total) \(noun)", "\(checked) checked", "\(comparable) at pin and clean"]
        if noBaseline > 0 { parts.append("\(noBaseline) with no baseline") }
        if uncheckable > 0 { parts.append("\(uncheckable) COULD NOT BE CHECKED") }
        var line = parts.joined(separator: " · ")
        if uncheckable > 0 {
            line += "\n\nA corpus that could not be read is not a corpus that agrees. Clone it "
                + "from the remote above,\nor read this run as covering \(checked) of \(total)."
        }
        return line
    }

    private static func short(_ revision: String) -> String {
        String(revision.prefix(7))
    }
}
