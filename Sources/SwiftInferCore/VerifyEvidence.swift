import Foundation

/// Outcome of a `swift-infer verify` run, as persisted to
/// `.swiftinfer/verify-evidence.json`. The five categories match the
/// `--all-from-index` survey's classification (`SurveyOutcome` in
/// `SwiftInferCLI`) — this is the Core-level persisted-evidence
/// vocabulary, kept separate from the CLI survey-output type so Core
/// carries no CLI dependency and the two layers can diverge if needed.
///
/// - `measuredBothPass` — the property held across the default trial
///   budget and the edge-case-biased pass.
/// - `measuredEdgeCaseAdvisory` — held for the finite domain but a
///   curated edge case surfaced a counterexample.
/// - `measuredDefaultFails` — the default pass found a counterexample;
///   the property is verify-disproven.
/// - `measuredError` — the verify run reached execution but errored
///   (parse failure, unexpected exception).
/// - `architecturalCoveragePending` — the pick errored before reaching
///   `swift build` execution (unsupported carrier / pair / template,
///   or a reclassified build failure). Not yet measurable; not a
///   property verdict.
public enum VerifyEvidenceOutcome: String, Sendable, Equatable, Codable, CaseIterable {
    case measuredBothPass = "measured-bothPass"
    case measuredEdgeCaseAdvisory = "measured-edgeCaseAdvisory"
    case measuredDefaultFails = "measured-defaultFails"
    case measuredError = "measured-error"
    case architecturalCoveragePending = "architectural-coverage-pending"
}

/// One persisted verify outcome, keyed by suggestion identity.
///
/// The machine-evidence counterpart to `DecisionRecord` — deliberately
/// a separate value type in a separate file (`.swiftinfer/
/// verify-evidence.json`) rather than a field on `DecisionRecord`:
///
///   - **Orthogonal lifecycles.** A suggestion can carry verify
///     evidence with no user decision yet (the `verify` gesture is
///     independent of `--interactive` triage), and a user can decide
///     on a suggestion that was never verified. Folding evidence into
///     `DecisionRecord` would force one of `decision` / evidence to be
///     absent-but-present-in-shape.
///   - **No schema migration.** `Decisions` is at schema v2; adding an
///     evidence field would be a v3 bump with the v1→v2→v3 reader
///     compatibility dance. A parallel file with its own
///     `schemaVersion` avoids touching the decisions format at all.
public struct VerifyEvidence: Sendable, Equatable, Codable {

    /// Stable suggestion-identity hash in the canonical persisted form —
    /// `SuggestionIdentity.normalized`: 16-char uppercase hex, no `0x`
    /// prefix, matching `DecisionRecord.identityHash`. The join key
    /// against `decisions.json` and against `discover` suggestions.
    /// Note `SemanticIndexEntry.identityHash` uses the `0x`-prefixed
    /// `display` form — `VerifyEvidenceRecorder.normalizedIdentityHash`
    /// strips it on write.
    public let identityHash: String

    /// Template that produced the suggestion (`"round-trip"`,
    /// `"idempotence"`, etc.). Stored for human readability of the
    /// evidence file and so a consumer can annotate without a separate
    /// index lookup.
    public let template: String

    /// The verify verdict — see `VerifyEvidenceOutcome`.
    public let outcome: VerifyEvidenceOutcome

    /// Short human-readable detail: trial counts for `measuredBothPass`,
    /// the failing trial for `measuredDefaultFails`, the
    /// architectural-pending category for `architecturalCoveragePending`.
    /// `nil` when the outcome carries no extra detail.
    public let detail: String?

    /// Wall-clock time the verify run completed. ISO8601-encoded in
    /// JSON for human readability + cross-platform parsing.
    public let capturedAt: Date

    /// swift-infer version string that produced this evidence. Consumers
    /// reading evidence stamped by an older binary surface a staleness
    /// warning, mirroring the SemanticIndex staleness pattern.
    public let swiftInferVersion: String

    public init(
        identityHash: String,
        template: String,
        outcome: VerifyEvidenceOutcome,
        detail: String?,
        capturedAt: Date,
        swiftInferVersion: String
    ) {
        self.identityHash = identityHash
        self.template = template
        self.outcome = outcome
        self.detail = detail
        self.capturedAt = capturedAt
        self.swiftInferVersion = swiftInferVersion
    }
}

/// Top-level `.swiftinfer/verify-evidence.json` shape. Wraps the
/// evidence list with a schema version, mirroring `Decisions`.
///
/// `upserting` is the canonical mutator: a second verify run on the
/// same identity replaces the first — the latest run is the evidence
/// currently in effect (a re-run reflects a code or kit change worth
/// keeping).
public struct VerifyEvidenceLog: Sendable, Equatable, Codable {

    /// Bumped when the on-disk schema changes incompatibly. Ships at
    /// version `1` (v1.64). Loaders that see a higher number warn and
    /// load what they can — same posture as `Decisions`.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let records: [VerifyEvidence]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        records: [VerifyEvidence] = []
    ) {
        self.schemaVersion = schemaVersion
        self.records = records
    }

    /// The empty value — schema version present, no records yet.
    /// `VerifyEvidenceStore.load` returns this when the file is absent.
    public static let empty = Self()

    /// Look up evidence by suggestion-identity hash. Used by the
    /// `discover` explainability annotation ("does this suggestion have
    /// verify evidence?").
    public func record(for identityHash: String) -> VerifyEvidence? {
        records.first { $0.identityHash == identityHash }
    }

    /// Append-or-overwrite by identity. Returns a new log with the
    /// prior record for the same identity removed (if any) and the new
    /// record appended at the end — the trailing-append shape keeps
    /// re-saved JSON stable for previously-recorded evidence. Mirrors
    /// `Decisions.upserting`.
    public func upserting(_ record: VerifyEvidence) -> Self {
        let withoutPrior = records.filter { $0.identityHash != record.identityHash }
        return Self(
            schemaVersion: schemaVersion,
            records: withoutPrior + [record]
        )
    }

    /// Fold another `VerifyEvidenceLog` into this one (V1.69). Used by
    /// `swift-infer metrics` to aggregate `.swiftinfer/verify-evidence.json`
    /// across multiple `--decisions` corpora into one in-memory log for
    /// the §17.2 cross-reference. Identity-keyed; on collision the
    /// record with the later `capturedAt` wins (mirrors `upserting(_:)`'s
    /// "latest run in effect" posture and `Decisions.merge`). The result
    /// is sorted by `capturedAt` then `identityHash` so the in-memory
    /// aggregate is order-deterministic regardless of input ordering.
    public func merge(_ other: Self) -> Self {
        var byHash: [String: VerifyEvidence] = [:]
        for record in records + other.records {
            if let existing = byHash[record.identityHash],
               existing.capturedAt >= record.capturedAt {
                continue
            }
            byHash[record.identityHash] = record
        }
        let merged = byHash.values.sorted { lhs, rhs in
            if lhs.capturedAt != rhs.capturedAt { return lhs.capturedAt < rhs.capturedAt }
            return lhs.identityHash < rhs.identityHash
        }
        return Self(
            schemaVersion: max(schemaVersion, other.schemaVersion),
            records: merged
        )
    }
}
