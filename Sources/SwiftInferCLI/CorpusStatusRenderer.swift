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
            let revision = measurement.revision.map(short) ?? "(revision unrecoverable)"
            return "    \(measurement.apparatus)/\(measurement.kind)  \(measurement.takenOn)  "
                + "\(revision)  \(measurement.arm)\(expectation)"
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

        case .revisionUnrecoverable:
            return "REVISION UNRECOVERABLE — the baseline records no revision, so nothing here "
                + "can be compared against it. Re-run the measurement and record the revision; "
                + "fetching cannot help."
        }
    }

    /// A summary that can never read as a pass it did not earn.
    private static func summary(_ statuses: [CorpusStatus]) -> String {
        let total = statuses.count
        let uncheckable = statuses.filter { $0.pin == .uncheckable }.count
        let noBaseline = statuses.filter { $0.pin == .noBaseline }.count
        // Counted from the MEASUREMENTS, not from the pin, and the difference is load-bearing.
        // A lost revision on a `census` leaves the pin verdict correctly at `noBaseline` — there
        // genuinely is no baseline — so counting the pin would file the loss under a bucket that
        // reads *enqueued, never swept*, and a sweep would clear the bucket without recovering
        // anything. The registry's defect is a property of the record, so it is counted there.
        let unrecoverable = statuses.filter { status in
            status.entry.measurements.contains { $0.revision == nil }
        }.count
        let comparable = statuses.filter(\.pin.isComparable).count
        let checked = total - uncheckable
        let noun = total == 1 ? "corpus" : "corpora"
        var parts = ["\(total) \(noun)", "\(checked) checked", "\(comparable) at pin and clean"]
        if noBaseline > 0 { parts.append("\(noBaseline) with no baseline") }
        // Counted separately from `noBaseline` for the reason `CorpusPin` states: a measurement
        // exists, so "never swept" is false, and folding it in would hide a permanently
        // uncomparable row inside a bucket a sweep would clear.
        if unrecoverable > 0 { parts.append("\(unrecoverable) with an UNRECOVERABLE revision") }
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
