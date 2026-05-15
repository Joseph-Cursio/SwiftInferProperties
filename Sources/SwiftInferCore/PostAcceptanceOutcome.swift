import Foundation

/// V1.72 — outcome of a `swift-infer accept-check` re-run on a
/// previously-accepted suggestion. The post-acceptance counterpart to
/// `VerifyEvidenceOutcome`, but classified at a coarser, semantically-
/// distinct grain because the question is different:
///
///   - `VerifyEvidenceOutcome` answers "does the property hold right
///     now on this suggestion?" — the pre-acceptance signal.
///   - `PostAcceptanceOutcomeKind` answers "did the property the user
///     accepted *still hold* after the function evolved?" — the
///     regression signal that PRD §17.2's 5th metric needs.
///
/// Four-state classification:
///
///   - `stillPasses` — re-verify returned `measuredBothPass` or
///     `measuredEdgeCaseAdvisory`. The accepted property still holds.
///   - `nowFails` — re-verify returned `measuredDefaultFails`. The
///     property the user accepted is now disproven (regression
///     detected — this is the signal PRD §17.2 is really after).
///   - `obsolete` — the accepted suggestion's identity hash no longer
///     surfaces in the current SemanticIndex (function renamed,
///     removed, or evolved past the suggestion shape). Not a failure;
///     informative — and not a denominator entry for the rate.
///   - `error` — the re-verify gesture could not produce a verdict
///     (build failure, unsupported template/carrier/pair, runtime
///     error, or `architecturalCoveragePending`). Not measurable on
///     this run; excluded from the rate denominator.
///
/// **Why coarser than the five `VerifyEvidenceOutcome` states.** The
/// post-acceptance question collapses `bothPass` + `edgeCaseAdvisory`
/// (both = "property holds") and folds `measuredError` +
/// `architecturalCoveragePending` into one `error` bucket (both =
/// "couldn't measure"). The `obsolete` state has no
/// `VerifyEvidenceOutcome` analog — verify itself never reaches that
/// classification (it throws `.suggestionNotFound`), so the
/// accept-check command synthesizes it from the caught error.
public enum PostAcceptanceOutcomeKind: String, Sendable, Equatable, Codable, CaseIterable {
    case stillPasses = "still-passes"
    case nowFails = "now-fails"
    case obsolete
    case error
}

/// V1.72.B — one persisted post-acceptance outcome, keyed by suggestion
/// identity. Mirrors `VerifyEvidence`'s shape (single record + top-level
/// log + upsert by hash) but with semantically distinct fields: the
/// `originalAcceptedAt` anchor is the decision's timestamp at accept
/// time, and `checkedAt` is when this re-run captured the verdict. The
/// gap between them is the "how long has the accepted property been in
/// the wild?" signal §17.2's 5th metric needs.
///
/// **Why a separate file from `VerifyEvidence`.**
///   - **Different question.** Verify evidence answers "does this
///     suggestion's property hold at suggestion time?"; post-acceptance
///     answers "does the property the user already accepted still hold
///     as the function evolves?" — see PostAcceptanceOutcomeKind doc.
///   - **Different lifecycle.** Verify evidence accumulates as the user
///     re-runs `verify` against any picked suggestion; post-acceptance
///     accumulates only for suggestions the user accepted (so it joins
///     to `decisions.json`'s `accepted` records, not the full
///     SemanticIndex). Folding into `verify-evidence.json` would mix
///     two-different-questions records under the same identity hash.
///   - **No schema migration.** Adding a field to `VerifyEvidence`
///     would force a `VerifyEvidenceLog.schemaVersion` bump and the
///     v1→v2 reader-compatibility dance. A parallel file with its own
///     `schemaVersion` avoids touching either format.
public struct PostAcceptanceOutcome: Sendable, Equatable, Codable {

    /// Stable suggestion-identity hash in the canonical persisted
    /// form — 16-char uppercase hex, no `0x` prefix. Matches
    /// `DecisionRecord.identityHash` so the join against
    /// `decisions.json` (and the metric's render-time join) is direct.
    public let identityHash: String

    /// Template that produced the originally-accepted suggestion
    /// (`"round-trip"`, `"idempotence"`, etc.). Mirrored from the
    /// triggering `DecisionRecord.template` so the post-acceptance
    /// file is self-describing without a separate decisions join.
    public let template: String

    /// The four-state post-acceptance verdict — see
    /// `PostAcceptanceOutcomeKind`.
    public let outcome: PostAcceptanceOutcomeKind

    /// Short human-readable detail: the verify sub-outcome that
    /// produced the verdict (`"bothPass"`, `"defaultFails"`, etc.), or
    /// the reason an `.obsolete` / `.error` outcome was emitted (e.g.
    /// `"identity hash no longer surfaces in current source"`). `nil`
    /// when the outcome carries no extra detail.
    public let detail: String?

    /// The decision-time timestamp from the source `DecisionRecord` —
    /// when the user originally accepted this suggestion. Persisted on
    /// each post-acceptance record so a consumer (the §17.2 section)
    /// can compute "how long has the property been in the wild?"
    /// without needing to re-load `decisions.json`.
    public let originalAcceptedAt: Date

    /// Wall-clock time the accept-check re-run captured this verdict.
    /// ISO8601-encoded in JSON for human readability + cross-platform
    /// parsing — mirrors `VerifyEvidence.capturedAt`.
    public let checkedAt: Date

    /// swift-infer version string that produced this outcome. A
    /// consumer reading an outcome stamped by an older binary can
    /// surface a staleness warning, mirroring the verify-evidence
    /// and SemanticIndex staleness patterns.
    public let swiftInferVersion: String

    public init(
        identityHash: String,
        template: String,
        outcome: PostAcceptanceOutcomeKind,
        detail: String?,
        originalAcceptedAt: Date,
        checkedAt: Date,
        swiftInferVersion: String
    ) {
        self.identityHash = identityHash
        self.template = template
        self.outcome = outcome
        self.detail = detail
        self.originalAcceptedAt = originalAcceptedAt
        self.checkedAt = checkedAt
        self.swiftInferVersion = swiftInferVersion
    }
}

/// V1.72.B — top-level `.swiftinfer/post-acceptance-outcomes.json`
/// shape. Wraps the outcome list with a schema version so future
/// changes can be detected and migrated without silent data loss.
///
/// `upserting` is the canonical mutator: a second accept-check run on
/// the same identity replaces the first — the latest run is the
/// outcome currently in effect (the same posture as `VerifyEvidence`
/// and `Decisions`). The §17.2 metric renders the *current* state of
/// each accepted suggestion; historical re-runs are out of scope for
/// v1.72.
public struct PostAcceptanceOutcomeLog: Sendable, Equatable, Codable {

    /// Bumped when the on-disk schema changes incompatibly. Ships at
    /// version `1` (v1.72). Loaders that see a higher number warn and
    /// load what they can — same posture as `Decisions` and
    /// `VerifyEvidenceLog`.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let records: [PostAcceptanceOutcome]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        records: [PostAcceptanceOutcome] = []
    ) {
        self.schemaVersion = schemaVersion
        self.records = records
    }

    /// The empty value — schema version present, no records yet.
    /// `PostAcceptanceOutcomesStore.load` returns this when the file
    /// is absent.
    public static let empty = PostAcceptanceOutcomeLog()

    /// Look up outcome by suggestion-identity hash. Used by the
    /// §17.2 metric's render-time join.
    public func record(for identityHash: String) -> PostAcceptanceOutcome? {
        records.first { $0.identityHash == identityHash }
    }

    /// Append-or-overwrite by identity. Returns a new log with the
    /// prior record for the same identity removed (if any) and the
    /// new record appended at the end. The trailing-append shape
    /// keeps re-saved JSON stable for previously-recorded outcomes —
    /// mirrors `VerifyEvidenceLog.upserting`.
    public func upserting(_ record: PostAcceptanceOutcome) -> PostAcceptanceOutcomeLog {
        let withoutPrior = records.filter { $0.identityHash != record.identityHash }
        return PostAcceptanceOutcomeLog(
            schemaVersion: schemaVersion,
            records: withoutPrior + [record]
        )
    }

    /// Fold another `PostAcceptanceOutcomeLog` into this one. Used by
    /// `swift-infer metrics --decisions` to aggregate the
    /// `.swiftinfer/post-acceptance-outcomes.json` files across
    /// multiple benchmark corpora into one in-memory log for the
    /// §17.2 section's denominator. Identity-keyed; on collision the
    /// record with the later `checkedAt` wins (mirrors
    /// `upserting(_:)`'s "latest run in effect" posture). The result
    /// is sorted by `checkedAt` then `identityHash` so the in-memory
    /// aggregate is order-deterministic regardless of input ordering.
    public func merge(_ other: PostAcceptanceOutcomeLog) -> PostAcceptanceOutcomeLog {
        var byHash: [String: PostAcceptanceOutcome] = [:]
        for record in records + other.records {
            if let existing = byHash[record.identityHash],
               existing.checkedAt >= record.checkedAt {
                continue
            }
            byHash[record.identityHash] = record
        }
        let merged = byHash.values.sorted { lhs, rhs in
            if lhs.checkedAt != rhs.checkedAt { return lhs.checkedAt < rhs.checkedAt }
            return lhs.identityHash < rhs.identityHash
        }
        return PostAcceptanceOutcomeLog(
            schemaVersion: max(schemaVersion, other.schemaVersion),
            records: merged
        )
    }
}
