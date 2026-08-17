import Foundation
import Testing

/// CLAUDE.md's index and its long-form annotations are two halves of one table.
///
/// ## Why they are two files
///
/// CLAUDE.md loads into context at the start of every session. On 2026-08-17 it was
/// 158 KB, and 135 KB of that was annotation prose living in table cells — measurements,
/// rejected alternatives, standing constraints on live code. None of it is decoration, so
/// it moved to `docs/reference/index-annotations.md` rather than being trimmed, and
/// CLAUDE.md kept a one-line hook per row.
///
/// ## Why that needs a guard
///
/// A split index is only as good as the join. This repo's recurring defect is a *summary*
/// going stale while the *detail* is maintained — `docs/measurements/stale-summary-guard-declined.md`
/// records four text detectors for it, all refuted, and slice 3c survived a month as
/// "deferred" in an index quoting a doc whose own row said `BUILT`. Putting the summary
/// and the detail in different files makes that easier, not harder.
///
/// So the **Question column is the join**, asserted verbatim in both directions. It cannot
/// check that a hook still *describes* its annotation — no guard can, which is the finding
/// those four detectors produced — but it can insist that a row exists on both sides. A row
/// added to one file and forgotten in the other fails here on the next fast run.
///
/// The one asymmetry is deliberate: CLAUDE.md carries a row *for* the annotations file,
/// which cannot annotate itself.
@Suite("CLAUDE.md index — every row has an annotation, and every annotation has a row")
struct IndexAnnotationParityTests {

    static let annotationsPath = "docs/reference/index-annotations.md"

    @Test("every CLAUDE.md index row has an annotation")
    func everyRowIsAnnotated() throws {
        let missing = try questions(inFile: "CLAUDE.md")
            .filter { !$0.contains("where did the reasoning go") }
            .filter { try !questions(inFile: Self.annotationsPath).contains($0) }

        #expect(
            missing.isEmpty,
            """
            These rows are in CLAUDE.md's index with no annotation in \(Self.annotationsPath). \
            Add the annotation — the hook states a verdict, and the annotation is where what \
            was measured, against what bar, and what would reopen it actually lives:
            \(missing.sorted().joined(separator: "\n"))
            """
        )
    }

    @Test("every annotation has a CLAUDE.md index row")
    func everyAnnotationIsReachable() throws {
        let rows = try questions(inFile: "CLAUDE.md")
        let orphaned = try questions(inFile: Self.annotationsPath).filter { !rows.contains($0) }

        #expect(
            orphaned.isEmpty,
            """
            These annotations are unreachable from CLAUDE.md's index, which is the same \
            failure as an unreachable doc — nobody opens it, so nobody maintains it. Either \
            add the row back or retire the annotation:
            \(orphaned.sorted().joined(separator: "\n"))
            """
        )
    }

    /// **A parity check over two empty sets passes.** Both halves are parsed with the same
    /// table-row heuristic, so one formatting change could empty both at once and the suite
    /// would report a perfectly consistent index that it never read. The floor is far below
    /// the 68 rows present on 2026-08-17 — a smoke alarm for a parsing bug, not a metric.
    @Test("both halves of the table are actually being read")
    func populationsAreNotEmpty() throws {
        #expect(try questions(inFile: "CLAUDE.md").count >= 40)
        #expect(try questions(inFile: Self.annotationsPath).count >= 40)
    }

    /// The first cell of every table row, minus the header. Both files use one markdown
    /// table for the index and no other table, which is what makes the naive scan safe;
    /// if that changes, scope this to the section rather than loosening the comparison.
    func questions(inFile relative: String) throws -> [String] {
        let text = try String(
            contentsOf: URL(fileURLWithPath: DocCitationScanner.absolute(relative)),
            encoding: .utf8
        )
        return text.components(separatedBy: "\n")
            .filter { $0.hasPrefix("| ") }
            .map { $0.components(separatedBy: "|")[1].trimmingCharacters(in: .whitespaces) }
            .filter { $0 != "Question" }
    }
}
