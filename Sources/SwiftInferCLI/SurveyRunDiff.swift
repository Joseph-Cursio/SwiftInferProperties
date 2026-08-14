import Foundation
import SwiftInferCore

/// Row-level comparison of two `RetainedSurveyRun`s.
///
/// ## The design decision that matters: a bucket diff is not enough
///
/// §11.3's best result was two `BodySignalVisitor` rows that moved from
/// `unsupported-carrier: BodySignalVisitor` to `subject not visible to tests`. **Both are
/// Unverifiable.** The bucket count went 61 → 61 and a count-level diff would have reported
/// nothing at all, while what actually happened is that the tool stopped sending a reader to
/// write a `gen()` for a visitor whose subject is `private` anyway.
///
/// So a change of *cause* within one bucket is reported as loudly as a change of bucket. That
/// is the same lesson §9.9 drew from the other side — "a decline-reason count is a hypothesis,
/// not a finding, until the rows are opened" — with the rows opened mechanically instead of by
/// hand for the fifth time.
///
/// ## The second decision: the subject fingerprint splits the verdict changes
///
/// `SuggestionIdentity` deliberately omits the body (§10.2 — it also keys `decisions.json` and
/// the user's `// swiftinfer: skip` markers, which must survive a refactor), so a row keeps
/// its identity across an edit. That is exactly right for diffing *the same law about the same
/// subject*, and it means a verdict change has two very different readings:
///
///   - **the body changed too** — expected; the code moved and the verdict followed it.
///   - **the body is byte-identical** — the *tool* changed, or the run is not deterministic.
///     This is the alarming one, and it is the reading a count can never surface.
///
/// `SurveyRecord.subjectFingerprint` already carries what separates them. A `nil` on either
/// side means "cannot tell" and is reported as its own answer rather than folded into either
/// — the same posture `VerifyEvidence`'s missing-fingerprint gate takes.
enum SurveyRunDiff {

    /// Which of the reader-facing buckets a record lands in.
    ///
    /// Mirrors `ProveThenShowRenderer`'s classification so a diff speaks the vocabulary the
    /// reader saw, with one deliberate exception: Expected-to-hold and Disproven are **not**
    /// split here. That split is computed from tier plus coverage plus attribution at render
    /// time, and re-deriving it would be a second copy of a rule that has already moved once.
    /// A refutation is a refutation for diffing purposes; the retained run keeps the tier map
    /// so a reader can take the split from the report it came with.
    enum Bucket: String, Sendable {
        case proven = "Proven"
        case refuted = "Refuted"
        case unverifiable = "Unverifiable"
        case inconclusive = "Inconclusive"

        static func of(_ outcome: SwiftInferCommand.Verify.SurveyOutcome) -> Self {
            switch outcome {
            case .measuredBothPass: return .proven
            case .measuredDefaultFails: return .refuted
            case .architecturalCoveragePending: return .unverifiable
            case .measuredEdgeCaseAdvisory, .measuredError: return .inconclusive
            }
        }
    }

    /// What the fingerprint says about a row whose verdict moved.
    enum SubjectMovement: String, Sendable {
        /// The body changed too — the ordinary reading.
        case bodyChanged = "body changed"
        /// The body is byte-identical, so the change is in the tool or in the run. Read this.
        case bodyIdentical = "body IDENTICAL — the tool changed, not the code"
        /// One side or both carried no fingerprint. Not evidence either way.
        case unknown = "body unknown (no fingerprint on one side)"

        static func of(before: String?, after: String?) -> Self {
            guard let before, let after else { return .unknown }
            return before == after ? .bodyIdentical : .bodyChanged
        }
    }

    struct ChangedRow: Sendable, Equatable {
        let identityHash: String
        let subject: String
        let template: String
        let beforeBucket: Bucket
        let afterBucket: Bucket
        let beforeDetail: String?
        let afterDetail: String?
        let movement: SubjectMovement

        /// `true` when the bucket held and only the decline cause moved — the §11.3 case a
        /// count-level comparison cannot see.
        var isCauseOnly: Bool { beforeBucket == afterBucket }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.identityHash == rhs.identityHash
                && lhs.beforeBucket == rhs.beforeBucket && lhs.afterBucket == rhs.afterBucket
                && lhs.beforeDetail == rhs.beforeDetail && lhs.afterDetail == rhs.afterDetail
        }
    }

    struct Result: Sendable {
        let changed: [ChangedRow]
        let added: [SwiftInferCommand.Verify.SurveyRecord]
        let removed: [SwiftInferCommand.Verify.SurveyRecord]
        let beforeCounts: [Bucket: Int]
        let afterCounts: [Bucket: Int]
        /// Set when the two runs name different targets — a comparison the caller almost
        /// certainly did not mean, surfaced rather than silently performed.
        let targetMismatch: (before: String, after: String)?

        var isEmpty: Bool { changed.isEmpty && added.isEmpty && removed.isEmpty }
    }

    /// Compare two runs, keyed on `identityHash`.
    ///
    /// Duplicate identities within one run keep the LAST record, matching `IndexStore.upsert`'s
    /// behaviour so the diff cannot disagree with the index about which row is current.
    static func compare(before: RetainedSurveyRun, after: RetainedSurveyRun) -> Result {
        let beforeByIdentity = indexed(before.records)
        let afterByIdentity = indexed(after.records)

        var changed: [ChangedRow] = []
        for (identity, afterRecord) in afterByIdentity {
            guard let beforeRecord = beforeByIdentity[identity] else { continue }
            let beforeBucket = Bucket.of(beforeRecord.outcome)
            let afterBucket = Bucket.of(afterRecord.outcome)
            // Cause-only moves are IN, deliberately — see the type doc.
            guard beforeBucket != afterBucket
                || beforeRecord.outcomeDetail != afterRecord.outcomeDetail else { continue }
            changed.append(
                ChangedRow(
                    identityHash: identity,
                    subject: afterRecord.primaryFunctionName,
                    template: afterRecord.templateName,
                    beforeBucket: beforeBucket,
                    afterBucket: afterBucket,
                    beforeDetail: beforeRecord.outcomeDetail,
                    afterDetail: afterRecord.outcomeDetail,
                    movement: SubjectMovement.of(
                        before: beforeRecord.subjectFingerprint,
                        after: afterRecord.subjectFingerprint
                    )
                )
            )
        }

        let added = afterByIdentity
            .filter { beforeByIdentity[$0.key] == nil }
            .map(\.value)
        let removed = beforeByIdentity
            .filter { afterByIdentity[$0.key] == nil }
            .map(\.value)

        return Result(
            changed: changed.sorted { ($0.subject, $0.template) < ($1.subject, $1.template) },
            added: added.sorted { $0.primaryFunctionName < $1.primaryFunctionName },
            removed: removed.sorted { $0.primaryFunctionName < $1.primaryFunctionName },
            beforeCounts: counts(before.records),
            afterCounts: counts(after.records),
            targetMismatch: before.target == after.target
                ? nil : (before: before.target, after: after.target)
        )
    }

    private static func indexed(
        _ records: [SwiftInferCommand.Verify.SurveyRecord]
    ) -> [String: SwiftInferCommand.Verify.SurveyRecord] {
        var byIdentity: [String: SwiftInferCommand.Verify.SurveyRecord] = [:]
        for record in records { byIdentity[record.identityHash] = record }
        return byIdentity
    }

    private static func counts(
        _ records: [SwiftInferCommand.Verify.SurveyRecord]
    ) -> [Bucket: Int] {
        var tally: [Bucket: Int] = [:]
        for record in records { tally[Bucket.of(record.outcome), default: 0] += 1 }
        return tally
    }
}
