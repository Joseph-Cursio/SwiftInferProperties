import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

/// A build diagnostic names the verifier workdir, so two arms run from different directories
/// differ on every `build-failed` row. Measured on the GRDB generator experiment: 34 rows
/// reported changed, roughly 24 of them this and nothing else — the tool built to surface
/// cause-only changes was manufacturing them.
///
/// The rule is **compare normalised, show verbatim**: only the directory prefix is collapsed,
/// and only for comparison. The report still prints the real path, because a reader chasing a
/// build failure needs it.
@Suite("Survey run diff — workdir paths do not manufacture cause changes")
struct SurveyRunDiffPathNoiseTests {

    private typealias Record = SwiftInferCommand.Verify.SurveyRecord

    private func run(_ detail: String) -> RetainedSurveyRun {
        RetainedSurveyRun(
            schemaVersion: RetainedSurveyRun.currentSchemaVersion,
            label: "arm", capturedAt: Date(timeIntervalSince1970: 1_770_000_000),
            target: "T", subjectRevision: "/tmp/x @ abc", swiftInferVersion: "1.149.0",
            tiersByIdentity: [:],
            records: [record(detail: detail)]
        )
    }

    private func record(detail: String) -> Record {
        Record(
            identityHash: "A1", templateName: "idempotence",
            primaryFunctionName: "f(_:)", carrier: "String",
            outcome: .measuredError, outcomeDetail: detail,
            subjectFingerprint: "FP0000000000000A"
        )
    }

    @Test("the same failure from two different workdirs is not a change")
    func differentWorkdirIsNotAChange() {
        // The exact pair from the GRDB experiment, trimmed.
        let before = run("build-failed: exit=1: /private/tmp/x/grdb-corpus/.swiftinfer/"
            + "verify-workdir/shared-survey/Sources/VD73/main.swift:94:18: error: cannot "
            + "convert value of type 'SQLExpression'")
        let after = run("build-failed: exit=1: /private/tmp/x/grdb-gen/.swiftinfer/"
            + "verify-workdir/shared-survey/Sources/VD73/main.swift:94:18: error: cannot "
            + "convert value of type 'SQLExpression'")
        #expect(SurveyRunDiff.compare(before: before, after: after).changed.isEmpty)
    }

    @Test("a different diagnostic from the same workdir IS a change")
    func differentMessageIsStillAChange() {
        // The arm that stops the fix from over-reaching: if normalisation swallowed real
        // message changes, the tool would report nothing and look correct doing it.
        let before = run("build-failed: /tmp/a/main.swift:94:18: error: cannot find 'Foo'")
        let after = run("build-failed: /tmp/a/main.swift:94:18: error: cannot find 'Bar'")
        #expect(SurveyRunDiff.compare(before: before, after: after).changed.count == 1)
    }

    @Test("a moved line in the same file IS a change")
    func movedLineIsAChange() {
        // Line and column survive normalisation deliberately — only the directory goes.
        let before = run("build-failed: /tmp/a/main.swift:94:18: error: cannot find 'Foo'")
        let after = run("build-failed: /tmp/b/main.swift:120:18: error: cannot find 'Foo'")
        #expect(SurveyRunDiff.compare(before: before, after: after).changed.count == 1)
    }

    @Test("the report shows the real path, not the normalised one")
    func reportShowsTheRawDetail() {
        let before = run("build-failed: /tmp/a/main.swift:94:18: error: cannot find 'Foo'")
        let after = run("build-failed: /tmp/b/main.swift:94:18: error: cannot find 'Bar'")
        let rendered = SurveyRunDiffRenderer.render(
            SurveyRunDiff.compare(before: before, after: after), before: before, after: after
        )
        #expect(rendered.contains("/tmp/b/main.swift"))
        #expect(!rendered.contains("<path>"))
    }

    @Test("a truncated pair differing only by how much path ate the budget is not a change")
    func truncationShiftIsNotAChange() {
        // The real shape, and the reason path collapsing ALONE was not enough. Both details
        // are clipped to the same budget, so the longer directory name pushes the cut earlier
        // and leaves different tails: "'SQLExpression' …" against "'SQLExpression' to …".
        let before = run("build-failed: /tmp/x/grdb-corpus/.swiftinfer/w/main.swift:94:18: "
            + "error: cannot convert value of type 'SQLExpression' …")
        let after = run("build-failed: /tmp/x/grdb-gen/.swiftinfer/w/main.swift:94:18: "
            + "error: cannot convert value of type 'SQLExpression' to …")
        #expect(SurveyRunDiff.compare(before: before, after: after).changed.isEmpty)
    }

    @Test("a truncated pair whose visible message differs IS still a change")
    func truncatedButGenuinelyDifferentIsAChange() {
        // The arm that stops the truncation handling from swallowing real movement. Without
        // it, dropping the unreliable tail could be widened until nothing ever reports.
        let before = run("build-failed: /tmp/a/main.swift:9: error: cannot find 'Foo' here …")
        let after = run("build-failed: /tmp/a/main.swift:9: error: cannot find 'Bar' here …")
        #expect(SurveyRunDiff.compare(before: before, after: after).changed.count == 1)
    }

    @Test("a real cause change that survives truncation is reported")
    func realChangeUnderTruncationIsReported() {
        // The measured case: `unsupported-carrier: Row` becoming a build failure. Neither is
        // truncated, so this also pins that the truncation path is not entered needlessly.
        let before = run("unsupported-carrier: Row")
        let after = run("instance-method-shape-not-supported")
        #expect(SurveyRunDiff.compare(before: before, after: after).changed.count == 1)
    }

    @Test("normalisation collapses only directory prefixes")
    func normalisationIsNarrow() {
        #expect(SurveyRunDiff.normalisedDetail("/a/b/main.swift:9: oops") == "<path>/main.swift:9: oops")
        // Prose containing a slash is untouched — it is not an absolute path.
        #expect(SurveyRunDiff.normalisedDetail("either/or") == "either/or")
        #expect(SurveyRunDiff.normalisedDetail(nil) == nil)
    }
}
