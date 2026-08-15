import Foundation

/// Renders a `CensusRun` so the denominator is read before the counts.
///
/// **Corpora first, templates second, and that ordering is the whole point.** A census is read
/// for its zeros, and a zero means nothing without the list it was taken over — the two errors
/// this command exists to prevent were both a correct count under a misremembered list. Putting
/// the counts first would reproduce the habit in the output.
enum CensusRenderer {

    static func render(_ run: CensusRun, wroteTo path: String?) -> String {
        var lines: [String] = ["", "Catalog census — \(run.label)", ""]
        lines.append("  Corpora surveyed (the denominator), \(run.corpora.count):")
        for member in run.corpora {
            let revision = member.revision.map { String($0.prefix(7)) } ?? "(not a git tree)"
            let dirty = member.dirty ? " · DIRTY, so these rows count uncommitted work" : ""
            lines.append(
                "    \(member.id)  @ \(revision)  [\(member.pin)]  \(member.total) rows\(dirty)"
            )
        }
        lines.append("")
        lines.append("  Flags: \(run.flags)   ·   swift-infer \(run.swiftInferVersion)")
        lines.append("")

        let rows = run.rowsByTemplate
        lines.append("  Rows per template, \(rows.count) fired, \(run.total) total:")
        let width = rows.keys.map(\.count).max() ?? 0
        for (template, count) in rows.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }) {
            let padded = template.padding(
                toLength: max(width, template.count), withPad: " ", startingAt: 0
            )
            lines.append("    \(padded)  \(count)")
        }
        lines.append("")

        // Said every time, not only when it happens to be interesting. The absent set is what a
        // reader came for, and it is the one thing these counts cannot supply.
        lines.append("""
          A template absent from that list fired ZERO times ACROSS THESE \
        \(run.corpora.count) CORPORA — which is not the same as never firing. Read a zero \
        against the list above, and widen the list before concluding a template is dead.
        """)
        if let path { lines.append(contentsOf: ["", "  Written to \(path)"]) }
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
