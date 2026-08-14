import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

/// Guards for the retained-run artifact and its row-level diff.
///
/// **The arm that carries this suite is `causeOnlyChangeIsReported`.** §11.3's result was two
/// rows moving from `unsupported-carrier: BodySignalVisitor` to `subject not visible to
/// tests` — same bucket, different cause, invisible to the bucket counts that every previous
/// pass recorded. If that arm ever stops failing on a broken diff, this tool has become the
/// count comparison it was built to replace.
///
/// **The control arm is `identicalRunsProduceAnEmptyDiff`.** A diff that reports movement
/// between a run and itself would make every future comparison unreadable, and would do it
/// while looking busy — the same failure shape as a guard that is green because it cannot
/// fire (`docs/measurements/falsifier-naming-failure-modes.md`).
@Suite("Retained survey runs — row-level diff, including cause-only moves")
struct SurveyRunDiffTests {

    // MARK: - Fixtures

    private typealias Record = SwiftInferCommand.Verify.SurveyRecord
    private typealias Outcome = SwiftInferCommand.Verify.SurveyOutcome

    private func record(
        identity: String,
        subject: String = "subject(_:)",
        template: String = "idempotence",
        outcome: Outcome,
        detail: String? = nil,
        fingerprint: String? = "FINGERPRINT0000A"
    ) -> Record {
        Record(
            identityHash: identity,
            templateName: template,
            primaryFunctionName: subject,
            carrier: "String",
            outcome: outcome,
            outcomeDetail: detail,
            subjectFingerprint: fingerprint
        )
    }

    private func run(
        _ records: [Record],
        label: String = "test run",
        target: String = "SwiftInferCore"
    ) -> RetainedSurveyRun {
        RetainedSurveyRun(
            schemaVersion: RetainedSurveyRun.currentSchemaVersion,
            label: label,
            capturedAt: Date(timeIntervalSince1970: 1_770_000_000),
            target: target,
            subjectRevision: "/tmp/subject @ abc1234",
            swiftInferVersion: "1.149.0",
            tiersByIdentity: [:],
            records: records
        )
    }

    // MARK: - The control

    @Test("a run diffed against itself reports nothing")
    func identicalRunsProduceAnEmptyDiff() {
        let subject = run([
            record(identity: "A1", outcome: .measuredBothPass),
            record(identity: "B2", outcome: .architecturalCoveragePending, detail: "carrier: X"),
            record(identity: "C3", outcome: .measuredDefaultFails)
        ])
        let result = SurveyRunDiff.compare(before: subject, after: subject)
        #expect(result.isEmpty)
        #expect(result.changed.isEmpty)
        #expect(result.added.isEmpty)
        #expect(result.removed.isEmpty)
    }

    // MARK: - The arm this suite exists for

    @Test("a cause change inside one bucket is reported, though the counts are identical")
    func causeOnlyChangeIsReported() {
        // §11.3, exactly: Unverifiable before and after, and the whole finding is in the
        // cause. A bucket-count comparison sees 1 → 1 and reports nothing.
        let before = run([
            record(
                identity: "A1", subject: "isEmptyDictionaryLiteral(_:)",
                outcome: .architecturalCoveragePending,
                detail: "unsupported-carrier: BodySignalVisitor"
            )
        ])
        let after = run([
            record(
                identity: "A1", subject: "isEmptyDictionaryLiteral(_:)",
                outcome: .architecturalCoveragePending,
                detail: "not-a-candidate: subject not visible to tests"
            )
        ])

        let result = SurveyRunDiff.compare(before: before, after: after)

        // The counts really are identical — this is the precondition, asserted so the arm
        // cannot pass for the wrong reason if bucketing changes.
        #expect(result.beforeCounts[.unverifiable] == 1)
        #expect(result.afterCounts[.unverifiable] == 1)

        #expect(result.changed.count == 1)
        let row = try? #require(result.changed.first)
        #expect(row?.isCauseOnly == true)
        #expect(row?.beforeBucket == .unverifiable)
        #expect(row?.afterBucket == .unverifiable)
        #expect(row?.afterDetail == "not-a-candidate: subject not visible to tests")
    }

    @Test("a row that changed neither bucket nor cause is not reported")
    func unchangedRowIsNotReported() {
        // The negative half of the arm above. Without this, a diff that reports every row
        // would pass `causeOnlyChangeIsReported` and be useless.
        let before = run([
            record(identity: "A1", outcome: .architecturalCoveragePending, detail: "carrier: X")
        ])
        let after = run([
            record(identity: "A1", outcome: .architecturalCoveragePending, detail: "carrier: X")
        ])
        #expect(SurveyRunDiff.compare(before: before, after: after).changed.isEmpty)
    }

    // MARK: - Bucket movement

    @Test("a bucket change is reported and is not labelled cause-only")
    func bucketChangeIsReported() {
        let before = run([
            record(identity: "A1", outcome: .architecturalCoveragePending, detail: "carrier: X")
        ])
        let after = run([record(identity: "A1", outcome: .measuredBothPass, detail: "100 trials")])

        let result = SurveyRunDiff.compare(before: before, after: after)
        #expect(result.changed.count == 1)
        #expect(result.changed.first?.isCauseOnly == false)
        #expect(result.changed.first?.beforeBucket == .unverifiable)
        #expect(result.changed.first?.afterBucket == .proven)
    }

    @Test("added and removed picks are separated, not folded into changed")
    func addedAndRemovedAreSeparate() {
        let before = run([
            record(identity: "A1", subject: "stays(_:)", outcome: .measuredBothPass),
            record(identity: "GONE", subject: "deleted(_:)", outcome: .measuredBothPass)
        ])
        let after = run([
            record(identity: "A1", subject: "stays(_:)", outcome: .measuredBothPass),
            record(identity: "NEW", subject: "arrived(_:)", outcome: .measuredBothPass)
        ])

        let result = SurveyRunDiff.compare(before: before, after: after)
        #expect(result.changed.isEmpty)
        #expect(result.added.map(\.primaryFunctionName) == ["arrived(_:)"])
        #expect(result.removed.map(\.primaryFunctionName) == ["deleted(_:)"])
    }

    // MARK: - The fingerprint split

    @Test("a verdict change with an identical body is flagged as a TOOL change")
    func identicalBodyIsFlagged() {
        // The alarming reading, and the one a count can never surface: the law and the code
        // are byte-identical and the verdict moved anyway.
        let before = run([
            record(identity: "A1", outcome: .measuredBothPass, fingerprint: "SAMEBODY00000001")
        ])
        let after = run([
            record(identity: "A1", outcome: .measuredDefaultFails, fingerprint: "SAMEBODY00000001")
        ])
        #expect(SurveyRunDiff.compare(before: before, after: after).changed.first?.movement
            == .bodyIdentical)
    }

    @Test("a verdict change with a changed body is the ordinary reading")
    func changedBodyIsOrdinary() {
        let before = run([
            record(identity: "A1", outcome: .measuredBothPass, fingerprint: "OLDBODY000000001")
        ])
        let after = run([
            record(identity: "A1", outcome: .measuredDefaultFails, fingerprint: "NEWBODY000000001")
        ])
        #expect(SurveyRunDiff.compare(before: before, after: after).changed.first?.movement
            == .bodyChanged)
    }

    @Test("a missing fingerprint on either side reports unknown, never a false reading")
    func missingFingerprintIsUnknown() {
        // Folding "cannot tell" into either answer would make the alarming reading unreliable
        // in the direction that matters — the same posture the evidence staleness gate takes.
        let before = run([record(identity: "A1", outcome: .measuredBothPass, fingerprint: nil)])
        let after = run([
            record(identity: "A1", outcome: .measuredDefaultFails, fingerprint: "ANYTHING00000001")
        ])
        #expect(SurveyRunDiff.compare(before: before, after: after).changed.first?.movement
            == .unknown)
    }

    // MARK: - Guards on the comparison itself

    @Test("comparing two different targets is surfaced, not silently performed")
    func targetMismatchIsSurfaced() {
        let before = run([record(identity: "A1", outcome: .measuredBothPass)], target: "CoreA")
        let after = run([record(identity: "A1", outcome: .measuredBothPass)], target: "CoreB")
        let result = SurveyRunDiff.compare(before: before, after: after)
        #expect(result.targetMismatch?.before == "CoreA")
        #expect(result.targetMismatch?.after == "CoreB")
    }

    @Test("every survey outcome maps to a bucket")
    func everyOutcomeBuckets() {
        // Parameterised over the enum rather than a literal list, so a sixth outcome cannot
        // join without this failing to compile — the pattern `everyFamilyMarksItsCheck` uses.
        let outcomes: [Outcome] = [
            .measuredBothPass, .measuredEdgeCaseAdvisory, .measuredDefaultFails,
            .measuredError, .architecturalCoveragePending
        ]
        for outcome in outcomes {
            #expect(!SurveyRunDiff.Bucket.of(outcome).rawValue.isEmpty)
        }
        #expect(SurveyRunDiff.Bucket.of(.measuredError) == .inconclusive)
        #expect(SurveyRunDiff.Bucket.of(.measuredEdgeCaseAdvisory) == .inconclusive)
    }

    // MARK: - The artifact round-trips

    @Test("a retained run survives a write and a read unchanged")
    func retainedRunRoundTrips() throws {
        let original = run([
            record(identity: "A1", outcome: .measuredBothPass, detail: "100 trials"),
            record(
                identity: "B2", outcome: .architecturalCoveragePending,
                detail: "unsupported-carrier: Effect", fingerprint: nil
            )
        ], label: "SwiftInferCore @ fdae49f")

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("retained-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: destination) }
        try original.write(to: destination)
        let reloaded = try RetainedSurveyRun.read(from: destination)

        #expect(reloaded.label == original.label)
        #expect(reloaded.target == original.target)
        #expect(reloaded.subjectRevision == original.subjectRevision)
        #expect(reloaded.records.count == 2)
        // The nil fingerprint must survive as nil — if it decoded to "" the unknown reading
        // above would silently become a body-changed reading.
        let reloadedB2 = reloaded.records.first { $0.identityHash == "B2" }
        #expect(reloadedB2?.subjectFingerprint == nil)
        #expect(reloadedB2?.outcomeDetail == "unsupported-carrier: Effect")
        // A round-tripped run diffs clean against its original — the artifact is the thing
        // being guarded, not just the struct.
        #expect(SurveyRunDiff.compare(before: original, after: reloaded).isEmpty)
    }

    // MARK: - The empty report says so

    @Test("an empty diff renders an explicit statement, not silence")
    func emptyDiffIsStated() {
        let subject = run([record(identity: "A1", outcome: .measuredBothPass)])
        let rendered = SurveyRunDiffRenderer.render(
            SurveyRunDiff.compare(before: subject, after: subject),
            before: subject, after: subject
        )
        // §10.1 recorded an identical run as "the correct result and ... a control, not a
        // null". A blank report cannot say that, and reads as a broken diff.
        #expect(rendered.contains("identical at row level"))
        #expect(rendered.contains("control"))
    }

    @Test("a cause-only change reaches the rendered report")
    func causeOnlyChangeIsRendered() {
        // The diff engine and the renderer are separate failures: a correct diff whose
        // renderer drops cause-only rows is the same silence, one stage later.
        let before = run([
            record(
                identity: "A1", outcome: .architecturalCoveragePending,
                detail: "unsupported-carrier: BodySignalVisitor"
            )
        ])
        let after = run([
            record(
                identity: "A1", outcome: .architecturalCoveragePending,
                detail: "not-a-candidate: subject not visible to tests"
            )
        ])
        let rendered = SurveyRunDiffRenderer.render(
            SurveyRunDiff.compare(before: before, after: after), before: before, after: after
        )
        #expect(rendered.contains("cause changed"))
        #expect(rendered.contains("BodySignalVisitor"))
        #expect(rendered.contains("subject not visible to tests"))
        #expect(!rendered.contains("identical at row level"))
    }
}
